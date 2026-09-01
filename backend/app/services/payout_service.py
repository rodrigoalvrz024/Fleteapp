from sqlalchemy.orm import Session

from app.models.driver_payout import DriverPayout, DriverPayoutStatus
from app.models.freight import FreightStatus
from app.models.payment import Payment, PaymentStatus


def ensure_driver_payout(db: Session, payment: Payment) -> DriverPayout | None:
    if payment.status != PaymentStatus.authorized:
        return None

    freight = payment.freight
    if (
        not freight
        or freight.status != FreightStatus.completed
        or not freight.driver_id
        or freight.driver_receives is None
        or freight.driver_receives <= 0
    ):
        return None

    existing = (
        db.query(DriverPayout)
        .filter(DriverPayout.payment_id == payment.id)
        .first()
    )
    if existing:
        return existing

    payout = DriverPayout(
        payment_id=payment.id,
        freight_id=freight.id,
        driver_id=freight.driver_id,
        amount=freight.driver_receives,
        status=DriverPayoutStatus.pending,
    )
    db.add(payout)
    db.flush()
    return payout
