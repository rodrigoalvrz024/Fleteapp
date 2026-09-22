"""Shared eligibility and conservative scheduling for driver offers."""

import math
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models.freight import FreightRequest, FreightStatus
from app.models.freight_driver_decline import FreightDriverDecline
from app.models.payment import PaymentStatus
from app.services.driver_operational_service import driver_operational_blockers
from app.services.freight_matching_service import driver_matches_freight


def freight_is_open_offer(freight: FreightRequest) -> bool:
    return (
        freight.deleted_at is None
        and freight.status == FreightStatus.pending
        and freight.driver_id is None
        and freight.payment is not None
        and freight.payment.status == PaymentStatus.authorized
    )


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def driver_assignments(db: Session, driver_id: int) -> list[FreightRequest]:
    return db.query(FreightRequest).filter(
        FreightRequest.driver_id == driver_id,
        FreightRequest.status.in_([FreightStatus.accepted, FreightStatus.in_progress]),
    ).all()


def _reservation_window(freight: FreightRequest, now: datetime):
    start = (
        _utc(freight.scheduled_at)
        if freight.scheduled_at and not freight.is_urgent
        else now
    )
    duration = freight.estimated_duration_minutes
    if duration is None or not math.isfinite(duration) or duration <= 0:
        return None
    # Route duration excludes loading/unloading and travel between jobs.
    margin = 180 if freight.service_type == "moving" else 60
    return start, start + timedelta(minutes=duration + margin)


def schedule_conflicts(
    freight: FreightRequest,
    assignments: list[FreightRequest],
    *,
    now: datetime | None = None,
) -> bool:
    now = _utc(now or datetime.now(timezone.utc))
    others = [item for item in assignments if item.id != freight.id]
    if not others:
        return False
    candidate = _reservation_window(freight, now)
    if candidate is None:
        return True
    for assigned in others:
        # An ongoing or overdue service has no trustworthy end time yet.
        if assigned.status == FreightStatus.in_progress or assigned.is_urgent:
            return True
        window = _reservation_window(assigned, now)
        if window is None or window[0] <= now:
            return True
        if candidate[0] < window[1] and window[0] < candidate[1]:
            return True
    return False


def driver_can_receive_offer(db: Session, driver, freight: FreightRequest) -> bool:
    if (
        not freight_is_open_offer(freight)
        or driver.deleted_at is not None
        or not driver.is_available
        or driver_operational_blockers(driver)
        or not driver_matches_freight(driver, freight)
    ):
        return False
    declined = db.query(FreightDriverDecline.id).filter(
        FreightDriverDecline.freight_id == freight.id,
        FreightDriverDecline.driver_id == driver.id,
    ).first()
    return not declined and not schedule_conflicts(
        freight, driver_assignments(db, driver.id)
    )
