from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func
from sqlalchemy.orm import Session
from typing import List
from pydantic import BaseModel
from app.core.config import settings
from app.database import get_db
from app.models.driver_review_audit import DriverReviewAudit
from app.models.user import User
from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest, FreightStatus
from app.models.payment import Payment, PaymentStatus
from app.schemas.user import UserResponse
from app.core.security import require_role
from app.services.storage_service import (
    create_driver_document_view_token,
    decode_driver_document_view_token,
    is_external_document_ref,
    stream_private_document,
)

router = APIRouter(prefix="/admin", tags=["Administración"])

class RejectBody(BaseModel):
    reason: str

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
) -> None:
    db.add(
        DriverReviewAudit(
            driver_id=driver.id,
            admin_id=admin.id,
            action=action,
            status_before=status_before,
            status_after=status_after,
            reason=reason,
            documents_snapshot=_documents_snapshot(driver),
            vehicle_snapshot=_vehicle_snapshot(driver),
        )
    )

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
    db: Session = Depends(get_db),
    _=Depends(require_role("admin"))
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    user.is_active = False
    db.commit()
    return {"message": f"Usuario {user_id} suspendido"}

@router.put("/users/{user_id}/activate")
def activate_user(
    user_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_role("admin"))
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    user.is_active = True
    db.commit()
    return {"message": f"Usuario {user_id} activado"}

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
    driver.status           = DriverStatus.approved
    driver.rejection_reason = None
    _create_review_audit(
        db=db,
        driver=driver,
        admin=current_admin,
        action="approved",
        status_before=status_before,
        status_after=DriverStatus.approved.value,
    )
    db.commit()
    return {"message": f"Conductor {driver_id} aprobado"}

@router.put("/drivers/{driver_id}/reject")
def reject_driver(
    driver_id: int,
    body: RejectBody,
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
    driver.status = DriverStatus.suspended
    if hasattr(driver, "rejection_reason"):
        driver.rejection_reason = reason
    _create_review_audit(
        db=db,
        driver=driver,
        admin=current_admin,
        action="rejected",
        status_before=status_before,
        status_after=DriverStatus.suspended.value,
        reason=reason,
    )
    db.commit()
    return {"message": f"Conductor {driver_id} rechazado"}


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
