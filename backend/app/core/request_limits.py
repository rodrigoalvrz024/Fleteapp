from tempfile import SpooledTemporaryFile

import anyio
from starlette.concurrency import run_in_threadpool
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send


class RequestBodyLimitMiddleware:
    """Bound the entire HTTP body before parsers or endpoints can consume it."""

    def __init__(self, app: ASGIApp, max_bytes: int, timeout_seconds: float = 120,
                 max_buffered_requests: int = 32):
        if max_bytes < 1 or timeout_seconds <= 0 or max_buffered_requests < 1:
            raise ValueError("request limits must be positive")
        self.app = app
        self.max_bytes = max_bytes
        self.timeout_seconds = timeout_seconds
        self.max_buffered_requests = max_buffered_requests
        self._buffered_requests = 0

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def reject(code: int):
            scope.setdefault("state", {})["body_limit_rejected"] = True
            detail = {
                400: "Content-Length invalido.",
                408: "Se agoto el tiempo para recibir la solicitud.",
                413: "La solicitud supera el tamano permitido.",
                499: "La solicitud fue interrumpida.",
                503: "Hay demasiadas solicitudes. Intenta nuevamente.",
            }[code]
            headers = {"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"}
            if code == 503:
                headers["Retry-After"] = "3"
            response = JSONResponse(
                status_code=code, content={"detail": detail},
                headers=headers,
            )
            await response(scope, receive, send)

        lengths = [value for key, value in scope.get("headers", [])
                   if key.lower() == b"content-length"]
        expected = None
        if lengths:
            value = lengths[0]
            if (len(lengths) != 1 or not value or not value.isdigit()
                    or any(key.lower() == b"transfer-encoding" for key, _ in scope["headers"])):
                await reject(400)
                return
            # Avoid unbounded integer parsing for attacker-controlled headers.
            if len(value.lstrip(b"0")) > len(str(self.max_bytes)):
                await reject(413)
                return
            expected = int(value.lstrip(b"0") or b"0")
            if expected > self.max_bytes:
                await reject(413)
                return

        # No await between admission and increment: bound spools per ASGI worker
        # without building an unbounded queue of requests waiting for a slot.
        if self._buffered_requests >= self.max_buffered_requests:
            await reject(503)
            return
        self._buffered_requests += 1
        try:
            # Threaded I/O keeps disk writes off the event loop. Admission stays
            # held until downstream processing releases the replay file.
            memory_limit = min(self.max_bytes, 64 * 1024)
            with SpooledTemporaryFile(max_size=memory_limit) as body:
                total = 0
                rolled_to_disk = False
                rejection = None
                try:
                    with anyio.fail_after(self.timeout_seconds):
                        while True:
                            message = await receive()
                            if message["type"] == "http.disconnect":
                                rejection = 499
                                break
                            chunk = message.get("body", b"")
                            total += len(chunk)
                            if total > self.max_bytes:
                                rejection = 413
                                break
                            if expected is not None and total > expected:
                                rejection = 400
                                break
                            if total > memory_limit and not rolled_to_disk:
                                await run_in_threadpool(body.rollover)
                                rolled_to_disk = True
                            await run_in_threadpool(body.write, chunk)
                            if not message.get("more_body", False):
                                break
                except TimeoutError:
                    rejection = 408
                if rejection is not None:
                    await reject(rejection)
                    return
                if expected is not None and total != expected:
                    await reject(400)
                    return

                await run_in_threadpool(body.seek, 0)
                remaining = total
                finished = False

                async def replay():
                    nonlocal remaining, finished
                    if finished:
                        return await receive()
                    chunk = await run_in_threadpool(body.read, min(remaining, 64 * 1024))
                    remaining -= len(chunk)
                    finished = remaining == 0
                    return {"type": "http.request", "body": chunk, "more_body": not finished}

                await self.app(scope, replay, send)
        finally:
            self._buffered_requests -= 1
