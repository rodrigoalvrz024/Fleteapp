from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.rate_limit import check_rate_limit
from app.core.security import decode_token, get_current_user
from app.database import get_db
from app.models.user import User
from app.schemas.analytics import (
    AnalyticsEventCreate,
    AnalyticsEventResponse,
    AnalyticsPresenceUpdate,
)
from app.services.audit_service import record_audit_event

router = APIRouter(prefix="/analytics", tags=["Analitica"])
optional_bearer = HTTPBearer(auto_error=False)

PUBLIC_EVENTS = {
    "public.page_view",
    "public.cta_click",
    "public.audience_click",
}

AUTHENTICATED_EVENTS = {
    "app.screen_view",
    "app.screen_dwell",
    "chat_opened",
    "chat_message_sent",
    "chat_message_failed",
}

_SCREEN_METADATA_KEYS = {"source", "platform", "screen", "duration_seconds"}

ALLOWED_ENTITY_TYPES = {
    "public_page",
    "public_cta",
    "freight",
    "driver",
    "screen",
}
SENSITIVE_METADATA_KEYWORDS = {
    "password",
    "token",
    "authorization",
    "cookie",
    "email",
    "phone",
    "address",
    "document",
    "license",
    "rut",
}


def _optional_current_user(
    credentials: HTTPAuthorizationCredentials | None,
    db: Session,
) -> User | None:
    if not credentials:
        return None
    try:
        payload = decode_token(credentials.credentials)
    except HTTPException:
        return None
    user_id = payload.get("sub")
    if not user_id:
        return None
    try:
        user_id = int(user_id)
    except (TypeError, ValueError):
        return None
    return db.query(User).filter(User.id == user_id, User.is_active == True).first()  # noqa: E712


def _clean_metadata(value: Any, depth: int = 0) -> Any:
    if depth > 2:
        return None
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return value[:300]
    if isinstance(value, list):
        return [_clean_metadata(item, depth + 1) for item in value[:10]]
    if isinstance(value, dict):
        cleaned: dict[str, Any] = {}
        for key, item in list(value.items())[:30]:
            if not isinstance(key, str):
                continue
            if any(keyword in key.lower() for keyword in SENSITIVE_METADATA_KEYWORDS):
                continue
            cleaned[key[:60]] = _clean_metadata(item, depth + 1)
        return cleaned
    return str(value)[:300]


def _clean_event_metadata(event_type: str, value: dict[str, Any] | None) -> dict[str, Any]:
    cleaned = _clean_metadata(value or {})
    if not isinstance(cleaned, dict):
        return {}
    if event_type not in {"app.screen_view", "app.screen_dwell"}:
        return cleaned

    safe = {key: cleaned[key] for key in _SCREEN_METADATA_KEYS if key in cleaned}
    if event_type == "app.screen_dwell":
        duration = safe.get("duration_seconds")
        if not isinstance(duration, int) or isinstance(duration, bool):
            raise HTTPException(status_code=400, detail="Duracion de pantalla invalida")
        safe["duration_seconds"] = min(max(duration, 1), 14400)
    return safe


@router.post(
    "/events",
    response_model=AnalyticsEventResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def record_analytics_event(
    data: AnalyticsEventCreate,
    request: Request,
    db: Session = Depends(get_db),
    credentials: HTTPAuthorizationCredentials | None = Depends(optional_bearer),
):
    if data.event_type not in PUBLIC_EVENTS | AUTHENTICATED_EVENTS:
        raise HTTPException(status_code=400, detail="Evento no permitido")
    if data.entity_type not in ALLOWED_ENTITY_TYPES:
        raise HTTPException(status_code=400, detail="Entidad no permitida")

    current_user = _optional_current_user(credentials, db)
    if data.event_type in AUTHENTICATED_EVENTS and not current_user:
        raise HTTPException(status_code=401, detail="Autenticacion requerida")
    if current_user:
        check_rate_limit(
            request,
            scope="analytics-events-user",
            identifier=str(current_user.id),
            max_attempts=300,
            window_seconds=60,
        )
    else:
        check_rate_limit(
            request,
            scope="analytics-events-public",
            max_attempts=120,
            window_seconds=60,
        )

    record_audit_event(
        db,
        actor=current_user,
        entity_type=data.entity_type,
        entity_id=data.entity_id,
        event_type=data.event_type,
        request=request,
        metadata=_clean_event_metadata(data.event_type, data.metadata),
    )
    db.commit()
    return AnalyticsEventResponse(status="accepted")


@router.post("/presence", response_model=AnalyticsEventResponse)
def record_presence(
    data: AnalyticsPresenceUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    check_rate_limit(
        request,
        scope="analytics-presence-user",
        identifier=str(current_user.id),
        max_attempts=20,
        window_seconds=60,
    )

    screen = data.screen.strip()
    if not screen.startswith("/") or "?" in screen or "#" in screen:
        raise HTTPException(status_code=400, detail="Pantalla invalida")

    current_user.last_seen_at = datetime.now(timezone.utc)
    current_user.last_seen_screen = screen
    db.commit()
    return AnalyticsEventResponse(status="accepted")
