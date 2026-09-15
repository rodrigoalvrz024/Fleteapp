from collections import deque
from dataclasses import dataclass, field
from hashlib import sha256
from math import ceil
from threading import Lock
from time import monotonic

from fastapi import HTTPException, Request, status


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
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        # Proxies append their verified client address to the right. Reading the
        # first value lets a caller bypass limits by supplying its own header.
        return forwarded_for.rsplit(",", 1)[-1].strip()
    return request.client.host if request.client else "unknown"


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
