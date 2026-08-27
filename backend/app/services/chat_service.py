from dataclasses import dataclass

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.driver import Driver
from app.models.freight import FreightRequest, FreightStatus
from app.models.user import User, UserRole


CHAT_WRITABLE_STATUSES = {FreightStatus.accepted, FreightStatus.in_progress}


@dataclass(frozen=True)
class FreightChatAccess:
    peer_user_id: int
    peer_full_name: str
    peer_role: str
    peer_avatar_url: str | None
    is_writable: bool


def _status_value(freight: FreightRequest) -> FreightStatus:
    status = freight.status
    return status if isinstance(status, FreightStatus) else FreightStatus(str(status))


def _assigned_driver(db: Session, freight: FreightRequest) -> Driver | None:
    driver = getattr(freight, "driver", None)
    if driver is not None:
        return driver
    if not freight.driver_id:
        return None
    return db.query(Driver).filter(Driver.id == freight.driver_id).first()


def resolve_freight_chat_access(
    db: Session,
    freight: FreightRequest,
    current_user: User,
) -> FreightChatAccess:
    """Returns the peer only for the two users assigned to an actual freight."""

    driver = _assigned_driver(db, freight)
    if not driver:
        raise HTTPException(status_code=409, detail="El chat estara disponible al asignar un conductor")

    driver_user = getattr(driver, "user", None)
    if driver_user is None:
        driver_user = db.query(User).filter(User.id == driver.user_id).first()
    if driver_user is None:
        raise HTTPException(status_code=409, detail="El conductor asignado no esta disponible")

    if current_user.role == UserRole.client and freight.client_id == current_user.id:
        return FreightChatAccess(
            peer_user_id=driver_user.id,
            peer_full_name=driver_user.full_name or "Conductor",
            peer_role=UserRole.driver.value,
            peer_avatar_url=driver_user.avatar_url,
            is_writable=_status_value(freight) in CHAT_WRITABLE_STATUSES,
        )

    if current_user.role == UserRole.driver and driver.user_id == current_user.id:
        return FreightChatAccess(
            peer_user_id=freight.client_id,
            peer_full_name=(freight.client.full_name if getattr(freight, "client", None) else "Cliente"),
            peer_role=UserRole.client.value,
            peer_avatar_url=(freight.client.avatar_url if getattr(freight, "client", None) else None),
            is_writable=_status_value(freight) in CHAT_WRITABLE_STATUSES,
        )

    # Admin accounts deliberately do not bypass private trip conversations.
    raise HTTPException(status_code=403, detail="No tienes permiso para este chat")


def require_writable_chat(access: FreightChatAccess) -> None:
    if not access.is_writable:
        raise HTTPException(
            status_code=409,
            detail="El chat esta archivado y ya no admite mensajes nuevos",
        )
