from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from app.database import get_db
from app.models.user import User
from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest
from app.models.payment import Payment, PaymentStatus
from app.schemas.user import UserResponse
from app.core.security import require_role

router = APIRouter(prefix="/admin", tags=["Administración"])

@router.get("/users", response_model=List[UserResponse])
def list_users(skip: int = 0, limit: int = 50, db: Session = Depends(get_db), _=Depends(require_role("admin"))):
    return db.query(User).offset(skip).limit(limit).all()

@router.put("/users/{user_id}/suspend")
def suspend_user(user_id: int, db: Session = Depends(get_db), _=Depends(require_role("admin"))):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    user.is_active = False
    db.commit()
    return {"message": f"Usuario {user_id} suspendido"}

@router.put("/users/{user_id}/activate")
def activate_user(user_id: int, db: Session = Depends(get_db), _=Depends(require_role("admin"))):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    user.is_active = True
    db.commit()
    return {"message": f"Usuario {user_id} activado"}

@router.put("/drivers/{driver_id}/approve")
def approve_driver(driver_id: int, db: Session = Depends(get_db), _=Depends(require_role("admin"))):
    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Conductor no encontrado")
    driver.status = DriverStatus.approved
    db.commit()
    return {"message": f"Conductor {driver_id} aprobado"}

@router.get("/metrics")
def get_metrics(db: Session = Depends(get_db), _=Depends(require_role("admin"))):
    total_users = db.query(User).count()
    total_drivers = db.query(Driver).count()
    total_freights = db.query(FreightRequest).count()
    total_revenue = db.query(Payment).filter(Payment.status == PaymentStatus.authorized).all()
    revenue = sum(p.amount for p in total_revenue)
    return {
        "total_users": total_users,
        "total_drivers": total_drivers,
        "total_freights": total_freights,
        "total_revenue_clp": revenue,
    }