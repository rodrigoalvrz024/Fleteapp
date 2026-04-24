from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from pydantic import BaseModel
from app.database import get_db
from app.models.user import User
from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest
from app.models.payment import Payment, PaymentStatus
from app.schemas.user import UserResponse
from app.core.security import require_role

router = APIRouter(prefix="/admin", tags=["Administración"])

class RejectBody(BaseModel):
    reason: str

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
            "profile_image_url":  d.profile_image_url,
            "license_image_url":  d.license_image_url,
            "vehicle_doc_url":    d.vehicle_doc_url,
            "rejection_reason":   d.rejection_reason,
            "vehicles":           [
                {
                    "id":    v.id,
                    "brand": v.brand,
                    "model": v.model,
                    "year":  v.year,
                    "plate": v.plate,
                    "color": v.color,
                }
                for v in (d.vehicles or [])
            ],
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
    driver.status           = DriverStatus.rejected
    driver.rejection_reason = body.reason
    db.commit()
    return {"message": f"Conductor {driver_id} rechazado"}

# ── Métricas ───────────────────────────────────────────────

@router.get("/metrics")
def get_metrics(
    db: Session = Depends(get_db),
    _=Depends(require_role("admin"))
):
    total_users    = db.query(User).count()
    total_drivers  = db.query(Driver).count()
    total_freights = db.query(FreightRequest).count()
    payments       = db.query(Payment).filter(
        Payment.status == PaymentStatus.authorized).all()
    revenue = sum(p.amount for p in payments)
    return {
        "total_users":       total_users,
        "total_drivers":     total_drivers,
        "total_freights":    total_freights,
        "total_revenue_clp": revenue,
    }