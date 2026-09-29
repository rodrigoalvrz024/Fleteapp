from collections import deque
from dataclasses import dataclass, field
from hashlib import sha256
from ipaddress import ip_address
from math import ceil
from threading import Lock
from time import monotonic

from fastapi import HTTPException, Request, status
from app.core.config import settings


@dataclass
class _Bucket:
    limit: int
    window: int
    attempts: deque[float] = field(default_factory=deque)


_MAX_BUCKETS = 4096
_SWEEP_INTERVAL = 30
_NEXT_SWEEP = 0.0
_LOCK = Lock()
_BUCKETS: dict[tuple[str, bytes], _Bucket] = {}


def _client_ip(request: Request) -> str:
    source = settings.LAUNCH_CLIENT_IP_SOURCE
    value = None
    if source == "peer":
        # app.server disables Uvicorn rewriting so this is the transport peer.
        value = request.client.host if request.client else None
    elif source == "railway":
        # Opt-in only after verifying that untrusted callers cannot bypass the
        # Railway HTTP proxy. A header alone cannot establish this boundary.
        values = request.headers.getlist("x-real-ip")
        if len(values) == 1:
            value = values[0]
    try:
        if not isinstance(value, str) or not 1 <= len(value) <= 45 or "%" in value:
            raise ValueError("Invalid client IP")
        address = ip_address(value)
        # IPv4-mapped IPv6 and IPv4 must share a quota.
        return str(getattr(address, "ipv4_mapped", None) or address)
    except ValueError:
        request.state.client_ip_rejected = True
        raise HTTPException(status_code=503, detail="No fue posible validar la conexion. Intenta nuevamente.",
                            headers={"Retry-After": "30"}) from None


def check_rate_limit(
    request: Request,
    *,
    scope: str,
    max_attempts: int,
    window_seconds: int,
    identifier: str | None = None,
) -> None:
    global _NEXT_SWEEP
    if (type(max_attempts) is not int or not 1 <= max_attempts <= 1000
            or type(window_seconds) is not int or not 1 <= window_seconds <= 86400
            or not isinstance(scope, str) or not 1 <= len(scope) <= 128):
        raise ValueError("Invalid rate-limit policy")
    # Fixed-size keys avoid retaining full emails or unbounded header strings.
    key = (scope, sha256((identifier or _client_ip(request)).encode("utf-8")).digest())
    with _LOCK:
        now = monotonic()
        if now >= _NEXT_SWEEP:
            expired = [key for key, bucket in _BUCKETS.items()
                       if not bucket.attempts or now - bucket.attempts[-1] >= bucket.window]
            for expired_key in expired:
                del _BUCKETS[expired_key]
            _NEXT_SWEEP = now + _SWEEP_INTERVAL
        bucket = _BUCKETS.get(key)
        if bucket is None:
            # Never evict an active quota: rotating identities must not reset it.
            if len(_BUCKETS) >= _MAX_BUCKETS:
                raise HTTPException(status_code=503, detail="Intenta nuevamente mas tarde.",
                                    headers={"Retry-After": str(_SWEEP_INTERVAL)})
            bucket = _BUCKETS[key] = _Bucket(max_attempts, window_seconds)
        if (bucket.limit, bucket.window) != (max_attempts, window_seconds):
            raise ValueError("Conflicting rate-limit policy")
        while bucket.attempts and now - bucket.attempts[0] >= window_seconds:
            bucket.attempts.popleft()
        if len(bucket.attempts) >= max_attempts:
            retry_after = max(1, ceil(bucket.attempts[0] + window_seconds - now))
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Demasiados intentos. Intenta nuevamente mas tarde.",
                headers={"Retry-After": str(retry_after)},
            )
        bucket.attempts.append(now)
