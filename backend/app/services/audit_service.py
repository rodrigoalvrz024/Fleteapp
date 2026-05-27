from fastapi import Request
from sqlalchemy.orm import Session

from app.models.audit_event import AuditEvent
from app.models.user import User


def _role_value(user: User | None) -> str | None:
    if not user:
        return None
    return user.role.value if hasattr(user.role, "value") else str(user.role)


def record_audit_event(
    db: Session,
    *,
    entity_type: str,
    entity_id: int | str,
    event_type: str,
    actor: User | None = None,
    before_data: dict | None = None,
    after_data: dict | None = None,
    reason: str | None = None,
    request: Request | None = None,
    metadata: dict | None = None,
) -> None:
    db.add(
        AuditEvent(
            actor_user_id=actor.id if actor else None,
            actor_role=_role_value(actor),
            entity_type=entity_type,
            entity_id=str(entity_id),
            event_type=event_type,
            before_data=before_data,
            after_data=after_data,
            reason=reason,
            ip_address=request.client.host if request and request.client else None,
            user_agent=request.headers.get("user-agent") if request else None,
            request_id=request.headers.get("x-request-id") if request else None,
            event_metadata=metadata,
        )
    )
