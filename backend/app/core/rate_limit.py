from collections import defaultdict, deque
from time import monotonic

from fastapi import HTTPException, Request, status


_BUCKETS: dict[str, deque[float]] = defaultdict(deque)


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
    key = f"{scope}:{identifier or _client_ip(request)}"
    now = monotonic()
    bucket = _BUCKETS[key]
    while bucket and now - bucket[0] > window_seconds:
        bucket.popleft()
    if len(bucket) >= max_attempts:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Demasiados intentos. Intenta nuevamente mas tarde.",
        )
    bucket.append(now)
