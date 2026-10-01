import asyncio
import unittest
from unittest.mock import patch
from tempfile import SpooledTemporaryFile

import httpx
from fastapi import Depends, FastAPI, File, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from app.core.request_limits import RequestBodyLimitMiddleware


class RequestBodyLimitTests(unittest.IsolatedAsyncioTestCase):
    async def invoke(self, chunks, *, headers=(), limit=8, disconnect=False):
        self.called = False
        self.received = b""
        self.sent = []
        events = [{"type": "http.request", "body": chunk,
                   "more_body": index < len(chunks) - 1 or disconnect}
                  for index, chunk in enumerate(chunks)]
        if disconnect:
            events.append({"type": "http.disconnect"})
        self.consumed = 0

        async def receive():
            self.consumed += 1
            return events.pop(0)

        async def send(message):
            self.sent.append(message)

        async def app(scope, receive, send):
            self.called = True
            while True:
                message = await receive()
                self.received += message.get("body", b"")
                if not message.get("more_body", False):
                    break

        await RequestBodyLimitMiddleware(app, limit)(
            {"type": "http", "headers": list(headers)}, receive, send)

    async def test_missing_length_and_chunked_bodies_cannot_exceed_limit(self):
        for headers in ([], [(b"transfer-encoding", b"chunked")]):
            with self.subTest(headers=headers):
                await self.invoke([b"1234", b"56789", b"not-read"], headers=headers)
                self.assertFalse(self.called)
                self.assertEqual(self.consumed, 2)
                self.assertEqual(self.sent[0]["status"], 413)

    async def test_rejects_oversized_length_without_reading_body(self):
        for value in (b"9", b"9" * 5000):
            await self.invoke([], headers=[(b"content-length", value)])
            self.assertFalse(self.called)
            self.assertEqual(self.consumed, 0)
            self.assertEqual(self.sent[0]["status"], 413)

    async def test_invalid_and_ambiguous_lengths(self):
        cases = [[(b"content-length", value)] for value in
                 (b"", b"-1", b"+1", b"1.0", b" 1", b"1,1")]
        cases += [[(b"content-length", b"1")] * 2,
                  [(b"content-length", b"1"), (b"transfer-encoding", b"chunked")]]
        for headers in cases:
            with self.subTest(headers=headers):
                await self.invoke([], headers=headers)
                self.assertFalse(self.called)
                self.assertEqual(self.sent[0]["status"], 400)

    async def test_declared_size_must_match_actual_size(self):
        for value in (b"2", b"7"):
            await self.invoke([b"123", b"456"], headers=[(b"content-length", value)])
            self.assertFalse(self.called)
            self.assertEqual(self.sent[0]["status"], 400)

    async def test_empty_and_exact_boundary_body_replayed_unchanged(self):
        for chunks in ([b""], [b"1234", b"5678"], [b"", b"12345678"]):
            await self.invoke(chunks)
            self.assertTrue(self.called)
            self.assertEqual(self.received, b"".join(chunks))
        await self.invoke([b"12345678"], headers=[(b"content-length", b"0008")])
        self.assertEqual(self.received, b"12345678")

    async def test_temporary_body_closed_on_success_rejection_and_disconnect(self):
        for chunks, disconnect in (([b"a" * 70000], False),
                                   ([b"a" * 70000, b"a" * 40000], False),
                                   ([b"a" * 70000], True)):
            with SpooledTemporaryFile(max_size=65536) as spool:
                with patch("app.core.request_limits.SpooledTemporaryFile", return_value=spool):
                    await self.invoke(chunks, limit=100000, disconnect=disconnect)
                self.assertTrue(spool.closed)
            if disconnect:
                self.assertFalse(self.called)
                self.assertEqual(self.sent[0]["status"], 499)

    async def test_large_chunk_rolls_to_disk_before_it_is_written(self):
        events = []
        with SpooledTemporaryFile(max_size=65536) as spool:
            write = spool.write
            rollover = spool.rollover

            def tracked_rollover():
                events.append("rollover")
                return rollover()

            def tracked_write(value):
                events.append("write")
                return write(value)

            with patch.object(spool, "rollover", side_effect=tracked_rollover):
                with patch.object(spool, "write", side_effect=tracked_write):
                    with patch("app.core.request_limits.SpooledTemporaryFile", return_value=spool):
                        await self.invoke([b"x" * 70000], limit=100000)
        self.assertEqual(events[:2], ["rollover", "write"])
        self.assertEqual(len(self.received), 70000)

    async def test_websocket_and_lifespan_bypass_http_body_handling(self):
        async def fail_receive():
            self.fail("HTTP body handling must not run")

        for kind in ("websocket", "lifespan"):
            scopes = []

            async def app(scope, receive, send):
                scopes.append(scope["type"])

            await RequestBodyLimitMiddleware(app, 8)({"type": kind}, fail_receive, None)
            self.assertEqual(scopes, [kind])

    async def test_spool_closes_if_application_fails_or_request_is_cancelled(self):
        async def fail_app(scope, receive, send):
            raise RuntimeError("synthetic failure")

        async def empty_body():
            return {"type": "http.request", "body": b"", "more_body": False}

        async def cancelled_receive():
            raise asyncio.CancelledError()

        for receive, error in ((empty_body, RuntimeError), (cancelled_receive, asyncio.CancelledError)):
            with SpooledTemporaryFile() as spool:
                with patch("app.core.request_limits.SpooledTemporaryFile", return_value=spool):
                    with self.assertRaises(error):
                        await RequestBodyLimitMiddleware(fail_app, 8)(
                            {"type": "http", "headers": []}, receive, None)
                self.assertTrue(spool.closed)

    async def test_stalled_upload_times_out_closes_spool_and_releases_slot(self):
        entered = []
        sent = []
        first = True

        async def app(scope, receive, send):
            entered.append(True)

        async def receive():
            nonlocal first
            if first:
                first = False
                return {"type": "http.request", "body": b"x" * 70000, "more_body": True}
            await asyncio.Event().wait()

        async def send(message):
            sent.append(message)

        limiter = RequestBodyLimitMiddleware(app, 100000, timeout_seconds=0.1, max_buffered_requests=1)
        with SpooledTemporaryFile(max_size=65536) as spool:
            with patch("app.core.request_limits.SpooledTemporaryFile", return_value=spool):
                await asyncio.wait_for(limiter({"type": "http", "headers": []}, receive, send), 2)
            self.assertTrue(spool.closed)
        self.assertEqual(entered, [])
        self.assertEqual(sent[0]["status"], 408)
        self.assertEqual(limiter._buffered_requests, 0)

    async def test_capacity_rejects_without_waiting_reading_or_creating_a_spool(self):
        started = asyncio.Event()
        hold = asyncio.Event()
        sent = []

        async def app(scope, receive, send):
            self.fail("Stalled requests must not reach endpoint")

        async def blocked_receive():
            started.set()
            await hold.wait()

        async def unexpected_receive():
            self.fail("Capacity rejection must not read request")

        async def send(message):
            sent.append(message)

        limiter = RequestBodyLimitMiddleware(app, 8, max_buffered_requests=1)
        first = asyncio.create_task(limiter({"type": "http", "headers": []}, blocked_receive, send))
        try:
            await asyncio.wait_for(started.wait(), 2)
            with patch("app.core.request_limits.SpooledTemporaryFile") as spool:
                await limiter({"type": "http", "headers": []}, unexpected_receive, send)
                spool.assert_not_called()
            self.assertEqual(sent[0]["status"], 503)
            self.assertIn((b"retry-after", b"3"), sent[0]["headers"])
        finally:
            first.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await first
        self.assertEqual(limiter._buffered_requests, 0)

    async def test_json_multipart_roles_and_cors_remain_functional(self):
        app = FastAPI()
        app.add_middleware(RequestBodyLimitMiddleware, max_bytes=1024)
        app.add_middleware(CORSMiddleware, allow_origins=["https://app.example.test"])
        entered = []

        def authenticated(request: Request):
            role = request.headers.get("x-test-role")
            if role not in {"client", "driver", "admin"}:
                raise HTTPException(401)
            return role

        @app.post("/json")
        def json_endpoint(data: dict, role=Depends(authenticated)):
            entered.append(role)
            return {"role": role, "data": data}

        @app.post("/file")
        async def upload(file: UploadFile = File(...), role=Depends(authenticated)):
            return {"size": len(await file.read()), "role": role}

        @app.post("/admin")
        def admin(role=Depends(authenticated)):
            if role != "admin":
                raise HTTPException(403)
            return {"ok": True}

        async with httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="http://test") as client:
            for role in ("client", "driver", "admin"):
                headers = {"x-test-role": role}
                response = await client.post("/json", json={"name": "prueba"}, headers=headers)
                self.assertEqual(response.json(), {"role": role, "data": {"name": "prueba"}})
                response = await client.post("/file", files={"file": ("test.jpg", b"fixture", "image/jpeg")}, headers=headers)
                self.assertEqual(response.json(), {"size": 7, "role": role})
                response = await client.post("/admin", headers=headers)
                self.assertEqual(response.status_code, 200 if role == "admin" else 403)
            response = await client.post("/json", json={})
            self.assertEqual(response.status_code, 401)

            async def oversized_stream():
                yield b"x" * 600
                yield b"x" * 600

            response = await client.post("/json", content=oversized_stream(),
                                         headers={"origin": "https://app.example.test"})
            self.assertEqual(response.status_code, 413)
            self.assertEqual(response.headers["access-control-allow-origin"], "https://app.example.test")
            self.assertEqual(response.headers["cache-control"], "no-store")
            self.assertEqual(entered, ["client", "driver", "admin"])


if __name__ == "__main__":
    unittest.main()
