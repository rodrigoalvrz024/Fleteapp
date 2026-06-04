from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.core.security import get_current_user, require_role
from app.database import get_db
from app.models.driver import Driver
from app.models.driver_payout import DriverPayout, DriverPayoutStatus
from app.models.user import User
from app.schemas.payout import DriverPayoutResponse, DriverPayoutUpdate
from app.services.audit_service import record_audit_event


router = APIRouter(prefix="/payouts", tags=["Liquidaciones conductores"])

VALID_TRANSITIONS = {
    DriverPayoutStatus.pending: {
        DriverPayoutStatus.scheduled,
        DriverPayoutStatus.paid,
        DriverPayoutStatus.failed,
    },
    DriverPayoutStatus.scheduled: {
        DriverPayoutStatus.pending,
        DriverPayoutStatus.paid,
        DriverPayoutStatus.failed,
    },
    DriverPayoutStatus.failed: {
        DriverPayoutStatus.pending,
        DriverPayoutStatus.scheduled,
        DriverPayoutStatus.paid,
    },
    DriverPayoutStatus.paid: set(),
}


@router.get("/me", response_model=List[DriverPayoutResponse])
def list_my_payouts(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Perfil de conductor no encontrado")
    return (
        db.query(DriverPayout)
        .filter(DriverPayout.driver_id == driver.id)
        .order_by(DriverPayout.created_at.desc())
        .all()
    )


@router.get("", response_model=List[DriverPayoutResponse])
def list_payouts(
    status: DriverPayoutStatus | None = None,
    db: Session = Depends(get_db),
    _=Depends(require_role("admin")),
):
    query = db.query(DriverPayout)
    if status:
        query = query.filter(DriverPayout.status == status)
    return query.order_by(DriverPayout.created_at.desc()).all()


@router.put("/{payout_id}", response_model=DriverPayoutResponse)
def update_payout(
    payout_id: int,
    data: DriverPayoutUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_admin: User = Depends(require_role("admin")),
):
    payout = db.query(DriverPayout).filter(DriverPayout.id == payout_id).first()
    if not payout:
        raise HTTPException(status_code=404, detail="Liquidacion no encontrada")
    if data.status == payout.status:
        return payout
    if data.status not in VALID_TRANSITIONS.get(payout.status, set()):
        raise HTTPException(
            status_code=400,
            detail=f"No se puede pasar de {payout.status.value} a {data.status.value}",
        )
    if data.status == DriverPayoutStatus.scheduled and not data.scheduled_for:
        raise HTTPException(status_code=400, detail="Indica la fecha programada")
    if data.status == DriverPayoutStatus.paid and not data.transfer_reference:
        raise HTTPException(
            status_code=400,
            detail="La referencia de transferencia es obligatoria",
        )
    if data.status == DriverPayoutStatus.failed and not data.note:
        raise HTTPException(status_code=400, detail="Indica el motivo del fallo")

    before = {
        "status": payout.status.value,
        "scheduled_for": payout.scheduled_for.isoformat()
        if payout.scheduled_for
        else None,
        "paid_at": payout.paid_at.isoformat() if payout.paid_at else None,
        "transfer_reference": payout.transfer_reference,
    }
    payout.status = data.status
    if data.status == DriverPayoutStatus.scheduled:
        payout.scheduled_for = data.scheduled_for
    elif data.status in {DriverPayoutStatus.pending, DriverPayoutStatus.failed}:
        payout.scheduled_for = None
    payout.transfer_reference = data.transfer_reference or payout.transfer_reference
    payout.note = data.note
    payout.paid_at = (
        datetime.now(timezone.utc)
        if data.status == DriverPayoutStatus.paid
        else None
    )
    payout.last_modified_by = current_admin.id
    record_audit_event(
        db,
        actor=current_admin,
        entity_type="driver_payout",
        entity_id=payout.id,
        event_type=f"driver_payout.{data.status.value}",
        before_data=before,
        after_data={
            "status": payout.status.value,
            "scheduled_for": payout.scheduled_for.isoformat()
            if payout.scheduled_for
            else None,
            "paid_at": payout.paid_at.isoformat() if payout.paid_at else None,
            "transfer_reference": payout.transfer_reference,
        },
        reason=data.note,
        request=request,
    )
    db.commit()
    db.refresh(payout)
    return payout
