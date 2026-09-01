from typing import Any

from app.database import SessionLocal
from app.models.freight import FreightRequest


async def notify_available_drivers(
    *,
    freight_id: int,
    title: str,
    body: str,
    data: dict[str, Any],
) -> None:
    """Deliver a paid freight notification without holding the API request open."""
    from app.services.notification_service import send_notification_to_drivers

    db = SessionLocal()
    try:
        freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
        if not freight:
            return
        await send_notification_to_drivers(
            db=db,
            title=title,
            body=body,
            data=data,
            freight=freight,
        )
    except Exception:
        print("[notifications] Could not notify available drivers")
    finally:
        db.close()
