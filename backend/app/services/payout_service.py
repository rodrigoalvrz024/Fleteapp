from sqlalchemy.orm import Session

from app.models.driver_payout import DriverPayout, DriverPayoutStatus
from app.models.payment import Payment, PaymentStatus


def ensure_driver_payout(db: Session, payment: Payment) -> DriverPayout | None:
    if payment.status != PaymentStatus.authorized:
        return None

    existing = (
        db.query(DriverPayout)
        .filter(DriverPayout.payment_id == payment.id)
        .first()
    )
    if existing:
        return existing

    freight = payment.freight
    if (
        not freight
        or not freight.driver_id
        or freight.driver_receives is None
        or freight.driver_receives <= 0
    ):
        return None

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
