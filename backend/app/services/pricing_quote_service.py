"""Server-side short lived quotes that prevent silent repricing on confirmation."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from hashlib import sha256
import json
import secrets
from typing import Any

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.pricing_quote import FreightPriceQuote


def _as_utc(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc).isoformat()
    return value.astimezone(timezone.utc).isoformat()


def quote_input_fingerprint(data: Any) -> str:
    """Bind an opaque quote to exactly the route and cargo the user priced."""
    payload = {
        "origin": [round(float(data.origin_lat), 6), round(float(data.origin_lng), 6)],
        "destination": [
            round(float(data.destination_lat), 6),
            round(float(data.destination_lng), 6),
        ],
        "cargo_description": " ".join(data.cargo_description.strip().lower().split()),
        "cargo_weight_kg": round(float(data.cargo_weight_kg), 3),
        "cargo_volume_m3": (
            round(float(data.cargo_volume_m3), 3)
            if data.cargo_volume_m3 is not None
            else None
        ),
        "helpers": int(data.requires_helpers),
        "extra_stops": int(data.extra_stops),
        "pickup_floor": data.pickup_floor,
        "delivery_floor": data.delivery_floor,
        "pickup_has_elevator": bool(data.pickup_has_elevator),
        "delivery_has_elevator": bool(data.delivery_has_elevator),
        "service_type": data.service_type,
        "is_urgent": bool(data.is_urgent),
        "scheduled_at": _as_utc(data.scheduled_at),
        "requested_vehicle_type": data.requested_vehicle_type,
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return sha256(encoded.encode("utf-8")).hexdigest()


def create_pricing_quote(
    db: Session,
    *,
    client_id: int,
    data: Any,
    route: dict,
    pricing: dict,
    now: datetime | None = None,
) -> FreightPriceQuote:
    if pricing.get("requires_manual_quote"):
        raise ValueError("Manual quote requests do not create automatic quotes")
    created_at = now or datetime.now(timezone.utc)
    quote = FreightPriceQuote(
        id=secrets.token_urlsafe(24),
        client_id=client_id,
        request_fingerprint=quote_input_fingerprint(data),
        route_distance_km=float(route["distance_km"]),
        route_duration_minutes=float(route["duration_minutes"]),
        route_provider=str(route["provider"]),
        route_calculated_at=route["calculated_at"],
        recommended_vehicle_type=pricing.get("recommended_vehicle_type"),
        selected_vehicle_type=pricing.get("selected_vehicle_type"),
        pricing_version=str(pricing["pricing_version"]),
        pricing_type=str(pricing["pricing_type"]),
        pricing_components=pricing,
        expires_at=created_at + timedelta(minutes=settings.PRICING_QUOTE_EXPIRE_MINUTES),
    )
    db.add(quote)
    return quote


def consume_pricing_quote(
    db: Session,
    *,
    quote_id: str,
    client_id: int,
    data: Any,
    now: datetime | None = None,
) -> FreightPriceQuote:
    """Lock and consume a quote once; pricing inputs must match exactly."""
    quote = (
        db.query(FreightPriceQuote)
        .filter(
            FreightPriceQuote.id == quote_id,
            FreightPriceQuote.client_id == client_id,
        )
        .with_for_update()
        .first()
    )
    if not quote or quote.used_at:
        raise HTTPException(status_code=409, detail="La tarifa ya no esta disponible. Recalcula el precio.")
    current = now or datetime.now(timezone.utc)
    expires_at = quote.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at <= current:
        raise HTTPException(status_code=409, detail="La tarifa vencio. Recalcula el precio.")
    if not secrets.compare_digest(quote.request_fingerprint, quote_input_fingerprint(data)):
        raise HTTPException(status_code=409, detail="La carga o ruta cambio. Recalcula el precio.")
    return quote
