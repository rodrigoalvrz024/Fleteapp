from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.rate_limit import check_rate_limit
from app.core.security import decode_token
from app.database import get_db
from app.models.user import User
from app.schemas.analytics import AnalyticsEventCreate, AnalyticsEventResponse
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
    "app.freight_detail_view",
    "app.driver_profile_view",
    "app.driver_available_freight_view",
}

ALLOWED_ENTITY_TYPES = {
    "public_page",
    "public_cta",
    "freight",
    "driver",
    "screen",
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
    return db.query(User).filter(User.id == int(user_id), User.is_active == True).first()  # noqa: E712


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
            cleaned[key[:60]] = _clean_metadata(item, depth + 1)
        return cleaned
    return str(value)[:300]


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
        metadata=_clean_metadata(data.metadata or {}),
    )
    db.commit()
    return AnalyticsEventResponse(status="accepted")
