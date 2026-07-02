from fastapi import HTTPException, Request
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

from app.core.config import settings


def _expected_audience() -> str:
    return (
        settings.CLOUD_TASKS_AUDIENCE
        or settings.CLOUD_TASKS_TARGET_BASE_URL
        or settings.PUBLIC_API_URL
    ).rstrip("/")


def verify_cloud_tasks_request(request: Request) -> dict:
    expected_service_account = settings.CLOUD_TASKS_SERVICE_ACCOUNT.strip()
    expected_audience = _expected_audience()
    if not expected_service_account or not expected_audience:
        raise HTTPException(
            status_code=503,
            detail="Cloud Tasks authentication is not configured",
        )

    auth_header = request.headers.get("authorization", "")
    scheme, _, token = auth_header.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Missing Cloud Tasks token")

    try:
        claims = id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            audience=expected_audience,
        )
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid Cloud Tasks token")

    caller_email = claims.get("email")
    if caller_email != expected_service_account:
        raise HTTPException(status_code=403, detail="Invalid Cloud Tasks caller")
    return claims
