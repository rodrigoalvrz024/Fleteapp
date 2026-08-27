import csv
import io
import json
from datetime import datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy import func
from sqlalchemy.orm import Session, selectinload
from typing import List
from pydantic import BaseModel, ConfigDict, Field
from app.core.config import settings
from app.database import get_db
from app.models.data_privacy_request import (
    DataPrivacyRequest,
    DataPrivacyRequestStatus,
)
from app.models.audit_event import AuditEvent
from app.models.driver_review_audit import DriverReviewAudit
from app.models.user import User
from app.models.user_consent import UserConsent
from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest, FreightStatus
from app.models.pricing_snapshot import FreightPricingSnapshot
from app.models.payment import Payment, PaymentStatus
from app.models.driver_payout import DriverPayout, DriverPayoutStatus
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
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    reason: str = Field(min_length=3, max_length=1000)


class DeleteDocumentsBody(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    reason: str | None = Field(default=None, max_length=1000)

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


def _csv_safe(value) -> str:
    text = "" if value is None else str(value)
    if text.startswith(("=", "+", "-", "@", "\t", "\r")):
        return f"'{text}"
    return text


def _parse_datetime_filter(value: str | None, *, end_of_day: bool = False) -> datetime | None:
    if not value:
        return None
    cleaned = value.strip()
    if not cleaned:
        return None
    try:
        if len(cleaned) == 10:
            day = datetime.fromisoformat(cleaned).date()
            if end_of_day:
                return datetime.combine(day + timedelta(days=1), time.min, timezone.utc)
            return datetime.combine(day, time.min, timezone.utc)
        parsed = datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed
    except ValueError as exc:
        raise HTTPException(400, "Fecha de historial invalida") from exc


def _normalize_audit_entity_type(entity_type: str | None) -> str | None:
    if entity_type == "privacy_request":
        return "data_privacy_request"
    return entity_type


def _as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _freight_amount(freight: FreightRequest) -> float:
    return float(freight.client_pays or freight.estimated_price or 0)


def _freight_platform_fee(freight: FreightRequest) -> float:
    return float(freight.platform_fee or 0)


def _snapshot_for_type(
    snapshots: list[FreightPricingSnapshot],
    *snapshot_types: str,
) -> FreightPricingSnapshot | None:
    for snapshot in reversed(snapshots):
        if snapshot.snapshot_type in snapshot_types:
            return snapshot
    return None


def _pricing_dataset_row(freight: FreightRequest) -> dict:
    snapshots = list(freight.pricing_snapshots or [])
    original = _snapshot_for_type(snapshots, "customer_confirmed")
    final = _snapshot_for_type(
        snapshots,
        "payment_authorized",
        "trip_completed",
        "trip_cancelled",
    ) or original
    source = original or final
    return {
        "freight_id": freight.id,
        "created_at": _datetime_or_none(freight.created_at),
        "requested_at": _datetime_or_none(freight.requested_at),
        "pricing_version": source.pricing_version if source else None,
        "pricing_type": source.pricing_type if source else None,
        "service_type": source.service_type if source else freight.service_type,
        "pickup_commune": source.pickup_commune if source else None,
        "dropoff_commune": source.dropoff_commune if source else None,
        "estimated_distance_km": (
            source.estimated_distance_km if source else freight.distance_km
        ),
        "actual_distance_km": (
            final.actual_distance_km if final else freight.actual_distance_km
        ),
        "estimated_duration_minutes": (
            source.estimated_duration_minutes
            if source
            else freight.estimated_duration_minutes
        ),
        "actual_duration_minutes": final.actual_duration_minutes if final else None,
        "estimated_weight_kg": (
            source.estimated_weight_kg if source else freight.cargo_weight_kg
        ),
        "estimated_volume_m3": (
            source.estimated_volume_m3 if source else freight.cargo_volume_m3
        ),
        "recommended_vehicle_type": (
            source.recommended_vehicle_type
            if source
            else freight.recommended_vehicle_type
        ),
        "selected_vehicle_type": (
            source.selected_vehicle_type if source else freight.selected_vehicle_type
        ),
        "actual_vehicle_id": final.actual_vehicle_id if final else freight.actual_vehicle_id,
        "actual_vehicle_type": final.actual_vehicle_type if final else None,
        "helpers_count": source.helpers_count if source else freight.requires_helpers,
        "urgent": source.urgent if source else freight.is_urgent,
        "estimated_customer_price": (
            source.estimated_customer_price if source else freight.estimated_price
        ),
        "accepted_customer_price": source.accepted_customer_price if source else None,
        "final_customer_price": (
            final.final_customer_price if final else freight.final_price
        ),
        "estimated_driver_earnings": (
            source.estimated_driver_earnings if source else freight.driver_receives
        ),
        "final_driver_earnings": final.final_driver_earnings if final else None,
        "estimated_platform_fee": (
            source.estimated_platform_fee if source else freight.platform_fee
        ),
        "final_platform_fee": final.final_platform_fee if final else None,
        "price_adjustment_amount": (
            final.price_adjustment_amount if final else None
        ),
        "price_adjustment_reason": (
            final.price_adjustment_reason if final else None
        ),
        "customer_confirmed_at": _datetime_or_none(freight.customer_confirmed_at),
        "driver_assigned_at": _datetime_or_none(freight.driver_assigned_at),
        "driver_accepted_at": _datetime_or_none(freight.driver_accepted_at),
        "driver_arrived_pickup_at": _datetime_or_none(
            freight.driver_arrived_pickup_at
        ),
        "trip_started_at": _datetime_or_none(freight.trip_started_at),
        "driver_arrived_destination_at": _datetime_or_none(
            freight.driver_arrived_destination_at
        ),
        "trip_completed_at": _datetime_or_none(freight.trip_completed_at),
        "cancelled_at": _datetime_or_none(freight.cancelled_at),
        "completed": freight.status == FreightStatus.completed,
        "cancelled": freight.status == FreightStatus.cancelled,
        "status": _status_value(freight.status),
    }


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
    return db.query(User).offset(max(skip, 0)).limit(min(max(limit, 1), 500)).all()

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


def _audit_actor_names(db: Session, events: list[AuditEvent]) -> dict[int, str]:
    actor_ids = sorted(
        {event.actor_user_id for event in events if event.actor_user_id is not None}
    )
    if not actor_ids:
        return {}
    return {
        user.id: user.full_name
        for user in db.query(User).filter(User.id.in_(actor_ids)).all()
    }


def _audit_event_to_dict(event: AuditEvent, actor_name: str | None = None) -> dict:
    return {
        "id": event.id,
        "occurred_at": _datetime_or_none(event.occurred_at),
        "actor_user_id": event.actor_user_id,
        "actor_name": actor_name,
        "actor_role": event.actor_role,
        "entity_type": event.entity_type,
        "entity_id": event.entity_id,
        "event_type": event.event_type,
        "before_data": event.before_data,
        "after_data": event.after_data,
        "reason": event.reason,
        "ip_address": event.ip_address,
        "user_agent": event.user_agent,
        "request_id": event.request_id,
        "metadata": event.event_metadata,
    }


def _build_audit_query(
    db: Session,
    entity_type: str | None = None,
    entity_id: str | None = None,
    event_type: str | None = None,
    actor_user_id: int | None = None,
    actor_role: str | None = None,
    occurred_from: str | None = None,
    occurred_to: str | None = None,
):
    query = db.query(AuditEvent)
    entity_type = _normalize_audit_entity_type(entity_type)
    if entity_type:
        query = query.filter(AuditEvent.entity_type == entity_type)
    if entity_id:
        query = query.filter(AuditEvent.entity_id == entity_id)
    if event_type:
        query = query.filter(AuditEvent.event_type == event_type)
    if actor_user_id is not None:
        query = query.filter(AuditEvent.actor_user_id == actor_user_id)
    if actor_role:
        query = query.filter(AuditEvent.actor_role == actor_role)

    from_dt = _parse_datetime_filter(occurred_from)
    to_dt = _parse_datetime_filter(occurred_to, end_of_day=True)
    if from_dt:
        query = query.filter(AuditEvent.occurred_at >= from_dt)
    if to_dt:
        query = query.filter(AuditEvent.occurred_at < to_dt)
    return query


def _top_event_entities(
    db: Session,
    *,
    since: datetime,
    event_type: str,
    entity_type: str,
    limit: int,
) -> list[dict]:
    rows = (
        db.query(
            AuditEvent.entity_id,
            func.count(AuditEvent.id),
            func.count(func.distinct(AuditEvent.actor_user_id)),
        )
        .filter(
            AuditEvent.occurred_at >= since,
            AuditEvent.event_type == event_type,
            AuditEvent.entity_type == entity_type,
        )
        .group_by(AuditEvent.entity_id)
        .order_by(func.count(AuditEvent.id).desc())
        .limit(limit)
        .all()
    )
    return [
        {
            "entity_id": entity_id,
            "views": count,
            "unique_authenticated_users": unique_users,
        }
        for entity_id, count, unique_users in rows
    ]


def _usage_insights(db: Session, *, since: datetime, now: datetime) -> dict:
    active_since = now - timedelta(minutes=2)
    active_filter = (
        User.is_active == True,  # noqa: E712
        User.last_seen_at.is_not(None),
        User.last_seen_at >= active_since,
    )
    active_now = db.query(func.count(User.id)).filter(*active_filter).scalar() or 0
    active_role_rows = (
        db.query(User.role, func.count(User.id))
        .filter(*active_filter)
        .group_by(User.role)
        .all()
    )
    active_users = (
        db.query(User)
        .filter(*active_filter)
        .order_by(User.last_seen_at.desc())
        .limit(25)
        .all()
    )
    active_by_role = {
        _status_value(role): count for role, count in active_role_rows
    }

    login_rows = (
        db.query(
            AuditEvent.actor_role,
            func.count(AuditEvent.id),
            func.count(func.distinct(AuditEvent.actor_user_id)),
        )
        .filter(
            AuditEvent.event_type == "auth.login_succeeded",
            AuditEvent.occurred_at >= since,
        )
        .group_by(AuditEvent.actor_role)
        .all()
    )
    logins_by_role = [
        {
            "role": role or "unknown",
            "count": count,
            "unique_users": unique_users,
        }
        for role, count, unique_users in login_rows
    ]
    logins_today = (
        db.query(func.count(AuditEvent.id))
        .filter(
            AuditEvent.event_type == "auth.login_succeeded",
            AuditEvent.occurred_at >= now - timedelta(hours=24),
        )
        .scalar()
        or 0
    )

    screen_stats: dict[str, dict] = {}
    dwell_events = (
        db.query(AuditEvent)
        .filter(
            AuditEvent.event_type == "app.screen_dwell",
            AuditEvent.entity_type == "screen",
            AuditEvent.occurred_at >= since,
        )
        .all()
    )
    for event in dwell_events:
        metadata = event.event_metadata or {}
        duration = metadata.get("duration_seconds")
        if not isinstance(duration, int) or isinstance(duration, bool):
            continue
        row = screen_stats.setdefault(
            event.entity_id,
            {"screen": event.entity_id, "visits": 0, "seconds": 0, "users": set()},
        )
        row["visits"] += 1
        row["seconds"] += duration
        if event.actor_user_id:
            row["users"].add(event.actor_user_id)

    top_screens = [
        {
            "screen": row["screen"],
            "visits": row["visits"],
            "total_seconds": row["seconds"],
            "average_seconds": round(row["seconds"] / row["visits"]),
            "unique_users": len(row["users"]),
        }
        for row in sorted(
            screen_stats.values(), key=lambda item: item["seconds"], reverse=True
        )[:10]
    ]

    return {
        "active_window_minutes": 2,
        "active_now": int(active_now),
        "active_by_role": active_by_role,
        "logins_period": sum(row["count"] for row in logins_by_role),
        "logins_last_24h": int(logins_today),
        "logins_by_role": logins_by_role,
        "top_screens_by_time": top_screens,
        "recent_active_users": [
            {
                "user_id": user.id,
                "full_name": user.full_name,
                "role": _status_value(user.role),
                "last_seen_at": _datetime_or_none(user.last_seen_at),
                "last_seen_screen": user.last_seen_screen,
                "last_login_at": _datetime_or_none(user.last_login_at),
            }
            for user in active_users
        ],
    }


@router.get("/insights/events")
def event_insights(
    days: int = 30,
    limit: int = 10,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    days = max(1, min(days, 365))
    limit = max(1, min(limit, 50))
    since = datetime.now(timezone.utc) - timedelta(days=days)

    event_rows = (
        db.query(
            AuditEvent.event_type,
            func.count(AuditEvent.id),
            func.count(func.distinct(AuditEvent.actor_user_id)),
        )
        .filter(AuditEvent.occurred_at >= since)
        .group_by(AuditEvent.event_type)
        .order_by(func.count(AuditEvent.id).desc())
        .all()
    )

    payload = {
        "period": {
            "days": days,
            "since": since.isoformat(),
        },
        "events_by_type": [
            {
                "event_type": event_type,
                "count": count,
                "unique_authenticated_users": unique_users,
            }
            for event_type, count, unique_users in event_rows
        ],
        "top_public_pages": _top_event_entities(
            db,
            since=since,
            event_type="public.page_view",
            entity_type="public_page",
            limit=limit,
        ),
        "top_public_ctas": _top_event_entities(
            db,
            since=since,
            event_type="public.cta_click",
            entity_type="public_cta",
            limit=limit,
        ),
        "top_freight_detail_views": _top_event_entities(
            db,
            since=since,
            event_type="app.freight_detail_view",
            entity_type="freight",
            limit=limit,
        ),
        "top_driver_profile_views": _top_event_entities(
            db,
            since=since,
            event_type="app.driver_profile_view",
            entity_type="driver",
            limit=limit,
        ),
        "product_usage": _usage_insights(db, since=since, now=datetime.now(timezone.utc)),
    }
    record_audit_event(
        db,
        actor=current_user,
        entity_type="admin_dashboard",
        entity_id="product_usage",
        event_type="admin.product_usage_viewed",
    )
    db.commit()
    return payload


@router.get("/operations")
def operational_overview(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    now = datetime.now(timezone.utc)
    since_hour = now - timedelta(hours=1)
    since_minute = now - timedelta(minutes=1)
    since_24h = now - timedelta(hours=24)
    since_14d = now - timedelta(days=14)

    freights_14d = (
        db.query(FreightRequest)
        .filter(FreightRequest.created_at >= since_14d)
        .all()
    )
    payments_14d = (
        db.query(Payment)
        .filter(Payment.created_at >= since_14d)
        .all()
    )

    minute_buckets = {
        (now.replace(second=0, microsecond=0) - timedelta(minutes=i)): {
            "count": 0,
            "client_pays_clp": 0.0,
            "platform_fee_clp": 0.0,
        }
        for i in range(59, -1, -1)
    }
    hourly_buckets = {
        (now.replace(minute=0, second=0, microsecond=0) - timedelta(hours=i)): {
            "count": 0,
            "client_pays_clp": 0.0,
            "platform_fee_clp": 0.0,
        }
        for i in range(23, -1, -1)
    }
    daily_buckets = {
        (now.date() - timedelta(days=i)): {
            "count": 0,
            "completed": 0,
            "cancelled": 0,
            "client_pays_clp": 0.0,
            "platform_fee_clp": 0.0,
        }
        for i in range(13, -1, -1)
    }

    freights_last_minute = 0
    freights_last_hour = 0
    freights_last_24h = 0
    completed_24h = 0
    cancelled_24h = 0
    active_clients_24h: set[int] = set()

    funnel = {
        "created": len(freights_14d),
        "accepted": 0,
        "started": 0,
        "completed": 0,
        "cancelled": 0,
    }
    gross_requested_14d = 0.0
    gross_completed_14d = 0.0
    platform_fee_potential_14d = 0.0
    platform_fee_completed_14d = 0.0
    gross_requested_24h = 0.0
    platform_fee_potential_24h = 0.0

    for freight in freights_14d:
        created_at = _as_utc(freight.created_at)
        if not created_at:
            continue
        amount = _freight_amount(freight)
        platform_fee = _freight_platform_fee(freight)
        status = _status_value(freight.status)

        gross_requested_14d += amount
        platform_fee_potential_14d += platform_fee

        if freight.accepted_at or freight.driver_id:
            funnel["accepted"] += 1
        if freight.started_at or status in {
            FreightStatus.in_progress.value,
            FreightStatus.completed.value,
        }:
            funnel["started"] += 1
        if status == FreightStatus.completed.value:
            funnel["completed"] += 1
            gross_completed_14d += amount
            platform_fee_completed_14d += platform_fee
        if status == FreightStatus.cancelled.value:
            funnel["cancelled"] += 1

        if created_at >= since_minute:
            freights_last_minute += 1
        if created_at >= since_hour:
            freights_last_hour += 1
        if created_at >= since_24h:
            freights_last_24h += 1
            active_clients_24h.add(freight.client_id)
            gross_requested_24h += amount
            platform_fee_potential_24h += platform_fee
            if status == FreightStatus.completed.value:
                completed_24h += 1
            if status == FreightStatus.cancelled.value:
                cancelled_24h += 1

        minute_key = created_at.replace(second=0, microsecond=0)
        if minute_key in minute_buckets:
            minute_buckets[minute_key]["count"] += 1
            minute_buckets[minute_key]["client_pays_clp"] += amount
            minute_buckets[minute_key]["platform_fee_clp"] += platform_fee

        hour_key = created_at.replace(minute=0, second=0, microsecond=0)
        if hour_key in hourly_buckets:
            hourly_buckets[hour_key]["count"] += 1
            hourly_buckets[hour_key]["client_pays_clp"] += amount
            hourly_buckets[hour_key]["platform_fee_clp"] += platform_fee

        day_key = created_at.date()
        if day_key in daily_buckets:
            daily_buckets[day_key]["count"] += 1
            daily_buckets[day_key]["client_pays_clp"] += amount
            daily_buckets[day_key]["platform_fee_clp"] += platform_fee
            if status == FreightStatus.completed.value:
                daily_buckets[day_key]["completed"] += 1
            if status == FreightStatus.cancelled.value:
                daily_buckets[day_key]["cancelled"] += 1

    created_count = max(funnel["created"], 1)
    freights_by_status = _count_by(db, FreightRequest.status)
    active_freights = (
        freights_by_status.get(FreightStatus.pending.value, 0)
        + freights_by_status.get(FreightStatus.accepted.value, 0)
        + freights_by_status.get(FreightStatus.in_progress.value, 0)
    )
    approved_drivers = (
        db.query(Driver).filter(Driver.status == DriverStatus.approved).count()
    )
    online_drivers = (
        db.query(Driver)
        .filter(
            Driver.status == DriverStatus.approved,
            Driver.is_available == True,
        )
        .count()
    )
    pending_drivers = (
        db.query(Driver).filter(Driver.status == DriverStatus.pending).count()
    )
    authorized_payments_14d = sum(
        float(payment.amount or 0)
        for payment in payments_14d
        if _status_value(payment.status) == PaymentStatus.authorized.value
    )

    return {
        "generated_at": now.isoformat(),
        "period": {
            "since_minute": since_minute.isoformat(),
            "since_hour": since_hour.isoformat(),
            "since_24h": since_24h.isoformat(),
            "since_14d": since_14d.isoformat(),
        },
        "realtime": {
            "freights_last_minute": freights_last_minute,
            "freights_last_hour": freights_last_hour,
            "freights_last_24h": freights_last_24h,
            "average_freights_per_minute_60m": round(freights_last_hour / 60, 2),
            "average_freights_per_hour_24h": round(freights_last_24h / 24, 2),
            "active_freights": active_freights,
            "pending_freights": freights_by_status.get(
                FreightStatus.pending.value, 0
            ),
            "accepted_freights": freights_by_status.get(
                FreightStatus.accepted.value, 0
            ),
            "in_progress_freights": freights_by_status.get(
                FreightStatus.in_progress.value, 0
            ),
            "completed_24h": completed_24h,
            "cancelled_24h": cancelled_24h,
            "online_drivers": online_drivers,
            "approved_drivers": approved_drivers,
            "pending_drivers": pending_drivers,
            "active_clients_24h": len(active_clients_24h),
            "gross_requested_24h_clp": round(gross_requested_24h),
            "platform_fee_potential_24h_clp": round(platform_fee_potential_24h),
        },
        "funnel_14d": {
            **funnel,
            "acceptance_rate": round((funnel["accepted"] / created_count) * 100, 1),
            "start_rate": round((funnel["started"] / created_count) * 100, 1),
            "completion_rate": round((funnel["completed"] / created_count) * 100, 1),
            "cancellation_rate": round((funnel["cancelled"] / created_count) * 100, 1),
        },
        "financial_14d": {
            "gross_requested_clp": round(gross_requested_14d),
            "gross_completed_clp": round(gross_completed_14d),
            "platform_fee_potential_clp": round(platform_fee_potential_14d),
            "platform_fee_completed_clp": round(platform_fee_completed_14d),
            "authorized_payments_clp": round(authorized_payments_14d),
        },
        "minute": [
            {
                "bucket": bucket.isoformat(),
                "count": values["count"],
                "client_pays_clp": round(values["client_pays_clp"]),
                "platform_fee_clp": round(values["platform_fee_clp"]),
            }
            for bucket, values in minute_buckets.items()
        ],
        "hourly": [
            {
                "bucket": bucket.isoformat(),
                "count": values["count"],
                "client_pays_clp": round(values["client_pays_clp"]),
                "platform_fee_clp": round(values["platform_fee_clp"]),
            }
            for bucket, values in hourly_buckets.items()
        ],
        "daily": [
            {
                "bucket": day.isoformat(),
                "count": values["count"],
                "completed": values["completed"],
                "cancelled": values["cancelled"],
                "client_pays_clp": round(values["client_pays_clp"]),
                "platform_fee_clp": round(values["platform_fee_clp"]),
            }
            for day, values in daily_buckets.items()
        ],
    }


@router.get("/audit-events")
def list_audit_events(
    entity_type: str | None = None,
    entity_id: str | None = None,
    event_type: str | None = None,
    actor_user_id: int | None = None,
    actor_role: str | None = None,
    occurred_from: str | None = None,
    occurred_to: str | None = None,
    limit: int = 100,
    db: Session = Depends(get_db),
    _=Depends(require_role("admin")),
):
    query = _build_audit_query(
        db,
        entity_type=entity_type,
        entity_id=entity_id,
        event_type=event_type,
        actor_user_id=actor_user_id,
        actor_role=actor_role,
        occurred_from=occurred_from,
        occurred_to=occurred_to,
    )
    events = (
        query.order_by(AuditEvent.occurred_at.desc())
        .limit(min(max(limit, 1), 500))
        .all()
    )
    actor_names = _audit_actor_names(db, events)
    return [
        _audit_event_to_dict(event, actor_names.get(event.actor_user_id))
        for event in events
    ]


@router.get("/audit-events/export")
def export_audit_events(
    entity_type: str | None = None,
    entity_id: str | None = None,
    event_type: str | None = None,
    actor_user_id: int | None = None,
    actor_role: str | None = None,
    occurred_from: str | None = None,
    occurred_to: str | None = None,
    limit: int = 1000,
    db: Session = Depends(get_db),
    _=Depends(require_role("admin")),
):
    events = (
        _build_audit_query(
            db,
            entity_type=entity_type,
            entity_id=entity_id,
            event_type=event_type,
            actor_user_id=actor_user_id,
            actor_role=actor_role,
            occurred_from=occurred_from,
            occurred_to=occurred_to,
        )
        .order_by(AuditEvent.occurred_at.desc())
        .limit(min(max(limit, 1), 5000))
        .all()
    )
    actor_names = _audit_actor_names(db, events)
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(
        [
            "id",
            "occurred_at",
            "actor_user_id",
            "actor_name",
            "actor_role",
            "entity_type",
            "entity_id",
            "event_type",
            "reason",
            "ip_address",
            "request_id",
            "before_data",
            "after_data",
            "metadata",
        ]
    )
    for event in events:
        writer.writerow(
            [
                _csv_safe(event.id),
                _csv_safe(_datetime_or_none(event.occurred_at)),
                _csv_safe(event.actor_user_id),
                _csv_safe(actor_names.get(event.actor_user_id, "")),
                _csv_safe(event.actor_role),
                _csv_safe(event.entity_type),
                _csv_safe(event.entity_id),
                _csv_safe(event.event_type),
                _csv_safe(event.reason),
                _csv_safe(event.ip_address),
                _csv_safe(event.request_id),
                _csv_safe(json.dumps(event.before_data or {}, ensure_ascii=False)),
                _csv_safe(json.dumps(event.after_data or {}, ensure_ascii=False)),
                _csv_safe(json.dumps(event.event_metadata or {}, ensure_ascii=False)),
            ]
        )
    filename = f"muvv_audit_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.csv"
    return Response(
        content=output.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _legal_consent_to_dict(consent: UserConsent, user: User) -> dict:
    return {
        "id": consent.id,
        "user_id": consent.user_id,
        "full_name": user.full_name,
        "email": user.email,
        "role": _status_value(user.role),
        "consent_type": consent.consent_type,
        "version": consent.version,
        "ip_address": consent.ip_address,
        "user_agent": consent.user_agent,
        "accepted_at": _datetime_or_none(consent.accepted_at),
    }


@router.get("/legal-consents")
def list_legal_consents(
    consent_type: str | None = None,
    limit: int = 100,
    db: Session = Depends(get_db),
    _=Depends(require_role("admin")),
):
    query = db.query(UserConsent, User).join(User, UserConsent.user_id == User.id)
    if consent_type:
        query = query.filter(UserConsent.consent_type == consent_type)
    rows = (
        query.order_by(UserConsent.accepted_at.desc())
        .limit(min(max(limit, 1), 500))
        .all()
    )
    return [_legal_consent_to_dict(consent, user) for consent, user in rows]


def _alert(
    severity: str,
    title: str,
    message: str,
    count: int,
    action: str,
) -> dict:
    return {
        "severity": severity,
        "title": title,
        "message": message,
        "count": count,
        "action": action,
    }


@router.get("/operational-alerts")
def list_operational_alerts(
    db: Session = Depends(get_db),
    _=Depends(require_role("admin")),
):
    now = datetime.now(timezone.utc)
    alerts = []
    backend_errors_24h = db.query(AuditEvent).filter(
        AuditEvent.event_type == "system.backend_error",
        AuditEvent.occurred_at >= now - timedelta(hours=24),
    ).count()
    pending_drivers = db.query(Driver).filter(
        Driver.status == DriverStatus.pending
    ).count()
    stale_pending_drivers = db.query(Driver).filter(
        Driver.status == DriverStatus.pending,
        Driver.created_at <= now - timedelta(hours=48),
    ).count()
    pending_privacy_requests = db.query(DataPrivacyRequest).filter(
        DataPrivacyRequest.status.in_(
            [
                DataPrivacyRequestStatus.pending,
                DataPrivacyRequestStatus.in_review,
            ]
        )
    ).count()
    pending_payouts = db.query(DriverPayout).filter(
        DriverPayout.status.in_(
            [DriverPayoutStatus.pending, DriverPayoutStatus.failed]
        )
    ).count()

    if backend_errors_24h:
        alerts.append(
            _alert(
                "critical",
                "Errores backend 24h",
                "Hay respuestas 500 registradas en la bitacora.",
                backend_errors_24h,
                "Revisar Historial filtrando accion system.backend_error",
            )
        )
    if pending_payouts:
        alerts.append(
            _alert(
                "warning",
                "Liquidaciones por resolver",
                "Hay pagos a conductores pendientes o fallidos.",
                pending_payouts,
                "Revisar pestaña Liquidaciones",
            )
        )
    if stale_pending_drivers:
        alerts.append(
            _alert(
                "warning",
                "Conductores esperando mas de 48h",
                "Hay solicitudes de conductor antiguas sin resolver.",
                stale_pending_drivers,
                "Revisar pestaña Revision",
            )
        )
    elif pending_drivers:
        alerts.append(
            _alert(
                "info",
                "Conductores esperando aprobacion",
                "Hay solicitudes de conductor listas para revisar.",
                pending_drivers,
                "Revisar pestaña Revision",
            )
        )
    if pending_privacy_requests:
        alerts.append(
            _alert(
                "warning",
                "Solicitudes de datos pendientes",
                "Hay solicitudes legales o de privacidad abiertas.",
                pending_privacy_requests,
                "Revisar pestaña Datos",
            )
        )

    if not alerts:
        alerts.append(
            _alert(
                "success",
                "Operacion sin alertas",
                "No hay errores recientes ni pendientes criticos.",
                0,
                "Mantener monitoreo diario",
            )
        )
    return alerts


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
    if not (driver.vehicle_doc_expiry or driver.circulation_permit_expiry):
        raise HTTPException(400, "Falta vencimiento del permiso de circulacion")
    if not driver.technical_review_url:
        raise HTTPException(400, "Falta revision tecnica")
    if not driver.technical_review_expiry:
        raise HTTPException(400, "Falta vencimiento de revision tecnica")
    if not driver.soap_url:
        raise HTTPException(400, "Falta SOAP")
    if not driver.soap_expiry:
        raise HTTPException(400, "Falta vencimiento de SOAP")
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
        if not settings.ALLOW_EXTERNAL_DOCUMENT_REFS:
            raise HTTPException(404, "Documento no disponible")
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
    payouts_by_status = _count_by(db, DriverPayout.status)
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
    driver_payout_clp = _sum_or_zero(db, DriverPayout.amount)
    pending_driver_payout_clp = _sum_or_zero(
        db,
        DriverPayout.amount,
        DriverPayout.status.in_(
            [
                DriverPayoutStatus.pending,
                DriverPayoutStatus.scheduled,
                DriverPayoutStatus.failed,
            ]
        ),
    )
    paid_driver_payout_clp = _sum_or_zero(
        db,
        DriverPayout.amount,
        DriverPayout.status == DriverPayoutStatus.paid,
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
        "payouts_by_status":              payouts_by_status,
        "pending_privacy_requests":       pending_privacy_requests,
        "authorized_payments_count":      authorized_payments_count,
        "authorized_payments_clp":        authorized_payments_clp,
        "average_authorized_ticket_clp":  average_authorized_ticket_clp,
        "gross_completed_clp":            gross_completed_clp,
        "platform_commission_clp":        platform_commission_clp,
        "pending_platform_commission_clp": pending_platform_commission_clp,
        "driver_payout_clp":              driver_payout_clp,
        "pending_driver_payout_clp":      pending_driver_payout_clp,
        "paid_driver_payout_clp":         paid_driver_payout_clp,
        # Compatibilidad: antes esta tarjeta se llamaba "Ingresos".
        "total_revenue_clp":              authorized_payments_clp,
    }


@router.get("/analytics/pricing-dataset")
def pricing_dataset(
    limit: int = 500,
    status: FreightStatus | None = None,
    created_from: str | None = None,
    created_to: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    """Return a privacy-aware, one-row-per-freight pricing calibration dataset."""
    limit = max(1, min(limit, 2_000))
    query = db.query(FreightRequest).options(
        selectinload(FreightRequest.pricing_snapshots)
    )
    if status:
        query = query.filter(FreightRequest.status == status)
    from_dt = _parse_datetime_filter(created_from)
    to_dt = _parse_datetime_filter(created_to, end_of_day=True)
    if from_dt:
        query = query.filter(FreightRequest.created_at >= from_dt)
    if to_dt:
        query = query.filter(FreightRequest.created_at < to_dt)
    freights = (
        query.order_by(FreightRequest.created_at.desc()).limit(limit).all()
    )
    rows = [_pricing_dataset_row(freight) for freight in freights]
    record_audit_event(
        db,
        actor=current_user,
        entity_type="pricing_dataset",
        entity_id="export",
        event_type="admin.pricing_dataset_viewed",
        metadata={"limit": limit, "status": _status_value(status) if status else None},
    )
    db.commit()
    return {
        "rows": rows,
        "count": len(rows),
        "schema_version": "pricing-dataset-v1",
    }
