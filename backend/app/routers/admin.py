from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session
from typing import List
from pydantic import BaseModel
from app.database import get_db
from app.models.user import User
from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest, FreightStatus
from app.models.payment import Payment, PaymentStatus
from app.schemas.user import UserResponse
from app.core.security import require_role

router = APIRouter(prefix="/admin", tags=["Administración"])

class RejectBody(BaseModel):
    reason: str

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
    drivers = (
        db.query(Driver, User)
        .join(User, Driver.user_id == User.id)
        .all()
    )
    return [
        {
            "id":                 d.id,
            "driver_id":          d.id,
            "user_id":            d.user_id,
            "full_name":          u.full_name,
            "email":              u.email,
            "phone":              u.phone,
            "status":             d.status.value
                                  if hasattr(d.status, 'value')
                                  else d.status,
            "profile_image_url":  getattr(d, "profile_image_url", None),
            "license_image_url":  getattr(d, "license_image_url", None),
            "vehicle_doc_url":    getattr(d, "vehicle_doc_url", None),
            "circulation_permit_url": getattr(d, "circulation_permit_url", None),
            "technical_review_url": getattr(d, "technical_review_url", None),
            "soap_url": getattr(d, "soap_url", None),
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
        for d, u in drivers
    ]

@router.put("/drivers/{driver_id}/approve")
def approve_driver(
    driver_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_role("admin"))
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
    driver.status           = DriverStatus.approved
    driver.rejection_reason = None
    db.commit()
    return {"message": f"Conductor {driver_id} aprobado"}

@router.put("/drivers/{driver_id}/reject")
def reject_driver(
    driver_id: int,
    body: RejectBody,
    db: Session = Depends(get_db),
    _=Depends(require_role("admin"))
):
    driver = db.query(Driver).filter(
        Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(404, "Conductor no encontrado")
    driver.status = DriverStatus.suspended
    if hasattr(driver, "rejection_reason"):
        driver.rejection_reason = body.reason
    db.commit()
    return {"message": f"Conductor {driver_id} rechazado"}

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
