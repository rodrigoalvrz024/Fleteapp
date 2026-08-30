from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.task_auth import verify_cloud_tasks_request
from app.database import get_db
from app.models.audit_event import AuditEvent
from app.models.freight import FreightRequest, FreightStatus
from app.services.audit_service import record_audit_event
from app.services.notification_service import send_notification_to_drivers

router = APIRouter(
    prefix="/internal/tasks",
    tags=["Tareas internas"],
    include_in_schema=False,
)


@router.post("/health")
async def cloud_tasks_health(request: Request):
    claims = verify_cloud_tasks_request(request)
    return {
        "status": "ok",
        "caller": claims.get("email"),
    }


@router.post("/freights/{freight_id}/notify-drivers")
async def notify_drivers_for_freight(
    freight_id: int,
    request: Request,
    db: Session = Depends(get_db),
):
    verify_cloud_tasks_request(request)
    if not settings.ENABLE_DRIVER_PUSH_NOTIFICATIONS:
        return {"status": "skipped", "reason": "driver_push_notifications_disabled"}

    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        return {"status": "skipped", "reason": "freight_not_found"}
    if freight.status != FreightStatus.pending or freight.driver_id is not None:
        return {"status": "skipped", "reason": "freight_not_available"}

    existing = (
        db.query(AuditEvent)
        .filter(
            AuditEvent.entity_type == "freight",
            AuditEvent.entity_id == str(freight_id),
            AuditEvent.event_type == "freight.driver_notifications_dispatched",
        )
        .first()
    )
    if existing:
        return {"status": "skipped", "reason": "already_dispatched"}

    title = "Nuevo flete disponible"
    body = (
        f"{'URGENTE' if freight.is_urgent else 'Programado'} - "
        f"${freight.client_pays:,.0f} CLP"
    )
    sent_count = await send_notification_to_drivers(
        db=db,
        title=title,
        body=body,
        data={
            "freight_id": str(freight.id),
            "type": "new_freight",
            "mode": freight.mode,
        },
        freight=freight,
    )
    record_audit_event(
        db,
        entity_type="freight",
        entity_id=freight.id,
        event_type="freight.driver_notifications_dispatched",
        after_data={"sent_count": sent_count},
        request=request,
        metadata={"source": "cloud_tasks"},
    )
    db.commit()
    return {"status": "ok", "sent_count": sent_count}
