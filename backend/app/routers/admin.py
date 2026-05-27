from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func
from sqlalchemy.orm import Session
from typing import List
from pydantic import BaseModel
from app.core.config import settings
from app.database import get_db
from app.models.data_privacy_request import (
    DataPrivacyRequest,
    DataPrivacyRequestStatus,
)
from app.models.audit_event import AuditEvent
from app.models.driver_review_audit import DriverReviewAudit
from app.models.user import User
from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest, FreightStatus
from app.models.payment import Payment, PaymentStatus
from app.schemas.privacy_request import PrivacyRequestAdminUpdate
from app.schemas.user import UserResponse
from app.core.security import require_role
from app.services.audit_service import record_audit_event
from app.services.storage_service import (
    create_driver_document_view_token,
    decode_driver_document_view_token,
    delete_private_document,
    is_external_document_ref,
    stream_private_document,
)

router = APIRouter(prefix="/admin", tags=["Administración"])

class RejectBody(BaseModel):
    reason: str


class DeleteDocumentsBody(BaseModel):
    reason: str | None = None

DOCUMENT_FIELDS = {
    "license_image": "license_image_url",
    "vehicle_doc": "vehicle_doc_url",
    "circulation_permit": "circulation_permit_url",
    "technical_review": "technical_review_url",
    "soap": "soap_url",
}

def _enum_key(value):
    return value.value if hasattr(value, "value") else str(value)

def _count_by(db: Session, column):
    return {
        _enum_key(key): count
        for key, count in db.query(column, func.count()).group_by(column).all()
    }

def _sum_or_zero(db: Session, column, *filters) -> float:
    query = db.query(func.coalesce(func.sum(column), 0))
    for item in filters:
        query = query.filter(item)
    return float(query.scalar() or 0)


def _datetime_or_none(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


def _status_value(status) -> str:
    return status.value if hasattr(status, "value") else str(status)


def _documents_snapshot(driver: Driver) -> dict:
    return {
        "license_image": bool(driver.license_image_url),
        "vehicle_doc": bool(driver.vehicle_doc_url),
        "circulation_permit": bool(driver.circulation_permit_url),
        "technical_review": bool(driver.technical_review_url),
        "soap": bool(driver.soap_url),
    }


def _vehicle_snapshot(driver: Driver) -> dict | None:
    if not driver.vehicle:
        return None
    return {
        "id": driver.vehicle.id,
        "brand": driver.vehicle.brand,
        "model": driver.vehicle.model,
        "year": driver.vehicle.year,
        "plate": driver.vehicle.plate,
        "color": driver.vehicle.color,
    }


def _review_to_dict(review: DriverReviewAudit, admin_name: str | None = None) -> dict:
    return {
        "id": review.id,
        "driver_id": review.driver_id,
        "admin_id": review.admin_id,
        "admin_name": admin_name,
        "action": review.action,
        "status_before": review.status_before,
        "status_after": review.status_after,
        "reason": review.reason,
        "documents_snapshot": review.documents_snapshot,
        "vehicle_snapshot": review.vehicle_snapshot,
        "created_at": review.created_at.isoformat() if review.created_at else None,
    }


def _create_review_audit(
    db: Session,
    driver: Driver,
    admin: User,
    action: str,
    status_before: str,
    status_after: str,
    reason: str | None = None,
    documents_snapshot: dict | None = None,
    vehicle_snapshot: dict | None = None,
) -> None:
    db.add(
        DriverReviewAudit(
            driver_id=driver.id,
            admin_id=admin.id,
            action=action,
            status_before=status_before,
            status_after=status_after,
            reason=reason,
            documents_snapshot=documents_snapshot or _documents_snapshot(driver),
            vehicle_snapshot=(
                vehicle_snapshot
                if vehicle_snapshot is not None
                else _vehicle_snapshot(driver)
            ),
        )
    )


def _has_driver_documents(driver: Driver) -> bool:
    return any(getattr(driver, field_name) for field_name in DOCUMENT_FIELDS.values())

@router.get("/users", response_model=List[UserResponse])
def list_users(
    skip: int = 0,
    limit: int = 50,
    db: Session = Depends(get_db),
    _=Depends(require_role("admin"))
):
    return db.query(User).offset(skip).limit(limit).all()

@router.put("/users/{user_id}/suspend")
def suspend_user(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_admin: User = Depends(require_role("admin"))
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    before_data = {"is_active": user.is_active}
    user.is_active = False
    user.last_modified_by = current_admin.id
    record_audit_event(
        db,
        actor=current_admin,
        entity_type="user",
        entity_id=user.id,
        event_type="user.suspended",
        before_data=before_data,
        after_data={"is_active": user.is_active},
        request=request,
    )
    db.commit()
    return {"message": f"Usuario {user_id} suspendido"}

@router.put("/users/{user_id}/activate")
def activate_user(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_admin: User = Depends(require_role("admin"))
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    before_data = {"is_active": user.is_active}
    user.is_active = True
    user.last_modified_by = current_admin.id
    record_audit_event(
        db,
        actor=current_admin,
        entity_type="user",
        entity_id=user.id,
        event_type="user.activated",
        before_data=before_data,
        after_data={"is_active": user.is_active},
        request=request,
    )
    db.commit()
    return {"message": f"Usuario {user_id} activado"}


def _privacy_request_to_dict(request: DataPrivacyRequest, user: User) -> dict:
    return {
        "id": request.id,
        "user_id": request.user_id,
        "full_name": user.full_name,
        "email": user.email,
        "phone": user.phone,
        "role": _status_value(user.role),
        "request_type": _status_value(request.request_type),
        "status": _status_value(request.status),
        "message": request.message,
        "admin_response": request.admin_response,
        "resolved_by": request.resolved_by,
        "resolved_at": _datetime_or_none(request.resolved_at),
        "created_at": _datetime_or_none(request.created_at),
        "updated_at": _datetime_or_none(request.updated_at),
    }


def _audit_event_to_dict(event: AuditEvent) -> dict:
    return {
        "id": event.id,
        "occurred_at": _datetime_or_none(event.occurred_at),
        "actor_user_id": event.actor_user_id,
        "actor_role": event.actor_role,
        "entity_type": event.entity_type,
        "entity_id": event.entity_id,
        "event_type": event.event_type,
        "before_data": event.before_data,
        "after_data": event.after_data,
        "reason": event.reason,
        "ip_address": event.ip_address,
        "request_id": event.request_id,
        "metadata": event.event_metadata,
    }


@router.get("/audit-events")
def list_audit_events(
    entity_type: str | None = None,
    entity_id: str | None = None,
    event_type: str | None = None,
    limit: int = 100,
    db: Session = Depends(get_db),
    _=Depends(require_role("admin")),
):
    query = db.query(AuditEvent)
    if entity_type:
        query = query.filter(AuditEvent.entity_type == entity_type)
    if entity_id:
        query = query.filter(AuditEvent.entity_id == entity_id)
    if event_type:
        query = query.filter(AuditEvent.event_type == event_type)
    events = (
        query.order_by(AuditEvent.occurred_at.desc())
        .limit(min(max(limit, 1), 500))
        .all()
    )
    return [_audit_event_to_dict(event) for event in events]


@router.get("/privacy-requests")
def list_privacy_requests(
    db: Session = Depends(get_db),
    _=Depends(require_role("admin")),
):
    rows = (
        db.query(DataPrivacyRequest, User)
        .join(User, DataPrivacyRequest.user_id == User.id)
        .order_by(DataPrivacyRequest.created_at.desc())
        .all()
    )
    return [_privacy_request_to_dict(request, user) for request, user in rows]


@router.put("/privacy-requests/{request_id}")
def update_privacy_request(
    request_id: int,
    data: PrivacyRequestAdminUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_admin: User = Depends(require_role("admin")),
):
    privacy_request = (
        db.query(DataPrivacyRequest)
        .filter(DataPrivacyRequest.id == request_id)
        .first()
    )
    if not privacy_request:
        raise HTTPException(404, "Solicitud no encontrada")
    if data.status == DataPrivacyRequestStatus.pending:
        raise HTTPException(400, "Usa en_revision, resuelta o rechazada")

    before_data = {
        "status": _status_value(privacy_request.status),
        "admin_response": privacy_request.admin_response,
        "resolved_by": privacy_request.resolved_by,
        "resolved_at": _datetime_or_none(privacy_request.resolved_at),
    }
    privacy_request.status = data.status
    privacy_request.admin_response = (
        data.admin_response.strip() if data.admin_response else None
    )
    privacy_request.last_modified_by = current_admin.id
    if data.status in (
        DataPrivacyRequestStatus.resolved,
        DataPrivacyRequestStatus.rejected,
    ):
        privacy_request.resolved_by = current_admin.id
        privacy_request.resolved_at = datetime.now(timezone.utc)
    else:
        privacy_request.resolved_by = None
        privacy_request.resolved_at = None
    record_audit_event(
        db,
        actor=current_admin,
        entity_type="data_privacy_request",
        entity_id=privacy_request.id,
        event_type="privacy_request.status_changed",
        before_data=before_data,
        after_data={
            "status": data.status.value,
            "admin_response": privacy_request.admin_response,
            "resolved_by": privacy_request.resolved_by,
            "resolved_at": _datetime_or_none(privacy_request.resolved_at),
        },
        reason=privacy_request.admin_response,
        request=request,
    )
    db.commit()
    return {"message": f"Solicitud {request_id} actualizada"}

# ── Conductores ────────────────────────────────────────────

@router.get("/drivers")
def list_drivers(
    db: Session = Depends(get_db),
    _=Depends(require_role("admin"))
):
    driver_rows = (
        db.query(Driver, User)
        .join(User, Driver.user_id == User.id)
        .all()
    )
    driver_ids = [driver.id for driver, _ in driver_rows]
    reviews_by_driver: dict[int, list[dict]] = {driver_id: [] for driver_id in driver_ids}
    if driver_ids:
        review_rows = (
            db.query(DriverReviewAudit, User)
            .join(User, DriverReviewAudit.admin_id == User.id)
            .filter(DriverReviewAudit.driver_id.in_(driver_ids))
            .order_by(DriverReviewAudit.created_at.desc())
            .all()
        )
        for review, admin in review_rows:
            bucket = reviews_by_driver.setdefault(review.driver_id, [])
            if len(bucket) < 5:
                bucket.append(_review_to_dict(review, admin.full_name))

    return [
        {
            "id":                 d.id,
            "driver_id":          d.id,
            "user_id":            d.user_id,
            "full_name":          u.full_name,
            "email":              u.email,
            "phone":              u.phone,
            "status":             _status_value(d.status),
            "documents":          _documents_snapshot(d),
            "documents_retention_until": (
                d.documents_retention_until.isoformat()
                if d.documents_retention_until
                else None
            ),
            "documents_deleted_at": (
                d.documents_deleted_at.isoformat()
                if d.documents_deleted_at
                else None
            ),
            "review_history":     reviews_by_driver.get(d.id, []),
            "rejection_reason":   getattr(d, "rejection_reason", None),
            "vehicles":           [
                {
                    "id":    d.vehicle.id,
                    "brand": d.vehicle.brand,
                    "model": d.vehicle.model,
                    "year":  d.vehicle.year,
                    "plate": d.vehicle.plate,
                    "color": d.vehicle.color,
                }
            ] if d.vehicle else [],
            "created_at": str(u.created_at),
        }
        for d, u in driver_rows
    ]

@router.put("/drivers/{driver_id}/approve")
def approve_driver(
    driver_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_admin: User = Depends(require_role("admin"))
):
    driver = db.query(Driver).filter(
        Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(404, "Conductor no encontrado")
    if not driver.vehicle:
        raise HTTPException(400, "El conductor no tiene vehiculo registrado")
    if not driver.license_image_url:
        raise HTTPException(400, "Falta licencia de conducir")
    if not (driver.vehicle_doc_url or driver.circulation_permit_url):
        raise HTTPException(400, "Falta permiso de circulacion")
    if not driver.technical_review_url:
        raise HTTPException(400, "Falta revision tecnica")
    if not driver.soap_url:
        raise HTTPException(400, "Falta SOAP")
    status_before = _status_value(driver.status)
    documents_before = _documents_snapshot(driver)
    driver.status           = DriverStatus.approved
    driver.rejection_reason = None
    driver.documents_retention_until = None
    driver.documents_deleted_at = None
    driver.last_modified_by = current_admin.id
    _create_review_audit(
        db=db,
        driver=driver,
        admin=current_admin,
        action="approved",
        status_before=status_before,
        status_after=DriverStatus.approved.value,
    )
    record_audit_event(
        db,
        actor=current_admin,
        entity_type="driver",
        entity_id=driver.id,
        event_type="driver.approved",
        before_data={"status": status_before, "documents": documents_before},
        after_data={
            "status": DriverStatus.approved.value,
            "documents": _documents_snapshot(driver),
        },
        request=request,
    )
    db.commit()
    return {"message": f"Conductor {driver_id} aprobado"}

@router.put("/drivers/{driver_id}/reject")
def reject_driver(
    driver_id: int,
    body: RejectBody,
    request: Request,
    db: Session = Depends(get_db),
    current_admin: User = Depends(require_role("admin"))
):
    reason = body.reason.strip()
    if not reason:
        raise HTTPException(400, "Debes indicar un motivo de rechazo")

    driver = db.query(Driver).filter(
        Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(404, "Conductor no encontrado")
    status_before = _status_value(driver.status)
    documents_before = _documents_snapshot(driver)
    driver.status = DriverStatus.suspended
    if hasattr(driver, "rejection_reason"):
        driver.rejection_reason = reason
    if _has_driver_documents(driver):
        driver.documents_retention_until = datetime.now(timezone.utc) + timedelta(
            days=settings.DRIVER_REJECTED_DOCUMENT_RETENTION_DAYS
        )
        driver.documents_deleted_at = None
    driver.last_modified_by = current_admin.id
    _create_review_audit(
        db=db,
        driver=driver,
        admin=current_admin,
        action="rejected",
        status_before=status_before,
        status_after=DriverStatus.suspended.value,
        reason=reason,
    )
    record_audit_event(
        db,
        actor=current_admin,
        entity_type="driver",
        entity_id=driver.id,
        event_type="driver.rejected",
        before_data={"status": status_before, "documents": documents_before},
        after_data={
            "status": DriverStatus.suspended.value,
            "documents_retention_until": _datetime_or_none(
                driver.documents_retention_until
            ),
        },
        reason=reason,
        request=request,
    )
    db.commit()
    return {"message": f"Conductor {driver_id} rechazado"}


@router.delete("/drivers/{driver_id}/documents")
def delete_driver_documents(
    driver_id: int,
    request: Request,
    body: DeleteDocumentsBody | None = None,
    db: Session = Depends(get_db),
    current_admin: User = Depends(require_role("admin")),
):
    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(404, "Conductor no encontrado")

    if driver.status != DriverStatus.suspended:
        raise HTTPException(
            400,
            "Solo se pueden borrar documentos de conductores suspendidos",
        )

    documents_snapshot = _documents_snapshot(driver)
    if not any(documents_snapshot.values()):
        raise HTTPException(400, "El conductor no tiene documentos para borrar")

    vehicle_snapshot = _vehicle_snapshot(driver)
    deletion_results = {}
    for document_type, field_name in DOCUMENT_FIELDS.items():
        document_ref = getattr(driver, field_name, None)
        deletion_results[document_type] = delete_private_document(document_ref)
        setattr(driver, field_name, None)

    driver.documents_deleted_at = datetime.now(timezone.utc)
    driver.documents_retention_until = None
    driver.last_modified_by = current_admin.id
    _create_review_audit(
        db=db,
        driver=driver,
        admin=current_admin,
        action="documents_deleted",
        status_before=_status_value(driver.status),
        status_after=_status_value(driver.status),
        reason=(body.reason.strip() if body and body.reason else None),
        documents_snapshot=documents_snapshot,
        vehicle_snapshot=vehicle_snapshot,
    )
    record_audit_event(
        db,
        actor=current_admin,
        entity_type="driver",
        entity_id=driver.id,
        event_type="driver.documents_deleted",
        before_data={"documents": documents_snapshot},
        after_data={
            "documents": _documents_snapshot(driver),
            "documents_deleted_at": _datetime_or_none(driver.documents_deleted_at),
            "deletion_results": deletion_results,
        },
        reason=(body.reason.strip() if body and body.reason else None),
        request=request,
    )
    db.commit()
    return {
        "message": f"Documentos del conductor {driver_id} eliminados",
        "results": deletion_results,
    }


@router.get("/drivers/{driver_id}/documents/{document_type}/view-url")
def get_driver_document_view_url(
    driver_id: int,
    document_type: str,
    request: Request,
    db: Session = Depends(get_db),
    _=Depends(require_role("admin")),
):
    document_field = DOCUMENT_FIELDS.get(document_type)
    if not document_field:
        raise HTTPException(404, "Documento no encontrado")

    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(404, "Conductor no encontrado")

    document_ref = getattr(driver, document_field, None)
    if not document_ref:
        raise HTTPException(404, "Documento no encontrado")

    if is_external_document_ref(document_ref):
        return {"url": document_ref, "expires_at": None}

    token, expires_at = create_driver_document_view_token(
        driver_id=driver.id,
        document_type=document_type,
        document_ref=document_ref,
    )
    base_url = (
        settings.PUBLIC_API_URL.rstrip("/")
        if settings.PUBLIC_API_URL
        else str(request.base_url).rstrip("/")
    )
    return {
        "url": f"{base_url}/admin/driver-documents/{token}",
        "expires_at": expires_at.isoformat(),
    }


@router.get("/driver-documents/{token}", name="view_driver_document")
def view_driver_document(
    token: str,
    db: Session = Depends(get_db),
):
    payload = decode_driver_document_view_token(token)
    document_type = payload.get("document_type")
    document_field = DOCUMENT_FIELDS.get(document_type)
    if not document_field:
        raise HTTPException(404, "Documento no disponible")

    driver = db.query(Driver).filter(Driver.id == payload.get("driver_id")).first()
    if not driver:
        raise HTTPException(404, "Documento no disponible")

    document_ref = getattr(driver, document_field, None)
    if not document_ref or document_ref != payload.get("document_ref"):
        raise HTTPException(404, "Documento no disponible")

    return stream_private_document(document_ref)

# ── Métricas ───────────────────────────────────────────────

@router.get("/metrics")
def get_metrics(
    db: Session = Depends(get_db),
    _=Depends(require_role("admin"))
):
    total_users      = db.query(User).count()
    active_users     = db.query(User).filter(User.is_active == True).count()
    total_drivers    = db.query(Driver).count()
    total_freights   = db.query(FreightRequest).count()
    users_by_role    = _count_by(db, User.role)
    drivers_by_status = _count_by(db, Driver.status)
    freights_by_status = _count_by(db, FreightRequest.status)
    payments_by_status = _count_by(db, Payment.status)
    pending_privacy_requests = db.query(DataPrivacyRequest).filter(
        DataPrivacyRequest.status.in_(
            [
                DataPrivacyRequestStatus.pending,
                DataPrivacyRequestStatus.in_review,
            ]
        )
    ).count()

    authorized_payments_clp = _sum_or_zero(
        db, Payment.amount, Payment.status == PaymentStatus.authorized
    )
    authorized_payments_count = payments_by_status.get(
        PaymentStatus.authorized.value, 0
    )
    platform_commission_clp = _sum_or_zero(
        db,
        FreightRequest.platform_fee,
        FreightRequest.status == FreightStatus.completed,
    )
    pending_platform_commission_clp = _sum_or_zero(
        db,
        FreightRequest.platform_fee,
        FreightRequest.status.in_([
            FreightStatus.pending,
            FreightStatus.accepted,
            FreightStatus.in_progress,
        ]),
    )
    driver_payout_clp = _sum_or_zero(
        db,
        FreightRequest.driver_receives,
        FreightRequest.status == FreightStatus.completed,
    )
    gross_completed_clp = _sum_or_zero(
        db,
        FreightRequest.client_pays,
        FreightRequest.status == FreightStatus.completed,
    )
    completed_freights = freights_by_status.get(FreightStatus.completed.value, 0)
    active_freights = (
        freights_by_status.get(FreightStatus.pending.value, 0)
        + freights_by_status.get(FreightStatus.accepted.value, 0)
        + freights_by_status.get(FreightStatus.in_progress.value, 0)
    )
    completion_rate = (
        round((completed_freights / total_freights) * 100, 1)
        if total_freights
        else 0
    )
    average_authorized_ticket_clp = (
        round(authorized_payments_clp / authorized_payments_count)
        if authorized_payments_count
        else 0
    )

    return {
        "total_users":                    total_users,
        "active_users":                   active_users,
        "inactive_users":                 total_users - active_users,
        "users_by_role":                  users_by_role,
        "total_drivers":                  total_drivers,
        "drivers_by_status":              drivers_by_status,
        "pending_drivers":                drivers_by_status.get(
            DriverStatus.pending.value, 0
        ),
        "approved_drivers":               drivers_by_status.get(
            DriverStatus.approved.value, 0
        ),
        "suspended_drivers":              drivers_by_status.get(
            DriverStatus.suspended.value, 0
        ),
        "total_freights":                 total_freights,
        "freights_by_status":             freights_by_status,
        "active_freights":                active_freights,
        "completed_freights":             completed_freights,
        "completion_rate":                completion_rate,
        "payments_by_status":             payments_by_status,
        "pending_privacy_requests":       pending_privacy_requests,
        "authorized_payments_count":      authorized_payments_count,
        "authorized_payments_clp":        authorized_payments_clp,
        "average_authorized_ticket_clp":  average_authorized_ticket_clp,
        "gross_completed_clp":            gross_completed_clp,
        "platform_commission_clp":        platform_commission_clp,
        "pending_platform_commission_clp": pending_platform_commission_clp,
        "driver_payout_clp":              driver_payout_clp,
        # Compatibilidad: antes esta tarjeta se llamaba "Ingresos".
        "total_revenue_clp":              authorized_payments_clp,
    }
