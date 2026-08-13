"""Immutable pricing and execution snapshots for freight analytics."""

from datetime import datetime, timezone
import unicodedata

from sqlalchemy.orm import Session

from app.models.freight import FreightRequest
from app.models.pricing_snapshot import FreightPricingSnapshot
from app.services.freight_service import PRICING_VERSION, normalize_service_type


def _as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _duration_minutes(
    started_at: datetime | None,
    completed_at: datetime | None,
) -> float | None:
    started = _as_utc(started_at)
    completed = _as_utc(completed_at)
    if not started or not completed or completed < started:
        return None
    return round((completed - started).total_seconds() / 60, 2)


def _normalized_text(value: str) -> str:
    return "".join(
        character
        for character in unicodedata.normalize("NFD", value.lower())
        if unicodedata.category(character) != "Mn"
    )


_KNOWN_COMMUNES = (
    "cerrillos",
    "cerro navia",
    "conchali",
    "el bosque",
    "estacion central",
    "huechuraba",
    "independencia",
    "la cisterna",
    "la florida",
    "la granja",
    "la pintana",
    "la reina",
    "las condes",
    "lo barnechea",
    "lo espejo",
    "lo prado",
    "macul",
    "maipu",
    "nunoa",
    "pedro aguirre cerda",
    "penalolen",
    "providencia",
    "pudahuel",
    "puente alto",
    "quilicura",
    "quinta normal",
    "recoleta",
    "renca",
    "san joaquin",
    "san miguel",
    "san ramon",
    "santiago",
    "vitacura",
)


def extract_commune(address: str | None) -> str | None:
    """Best-effort commune extraction without storing another full address."""
    if not address:
        return None
    normalized = _normalized_text(address)
    for commune in _KNOWN_COMMUNES:
        if commune in normalized:
            return " ".join(part.capitalize() for part in commune.split())
    return None


def _vehicle_snapshot(freight: FreightRequest) -> dict:
    driver = getattr(freight, "driver", None)
    vehicle = getattr(driver, "vehicle", None) if driver else None
    if not vehicle:
        return {}
    vehicle_type = (
        vehicle.type.value if hasattr(vehicle.type, "value") else str(vehicle.type)
    )
    return {
        "actual_vehicle_id": vehicle.id,
        "actual_vehicle_type": vehicle_type,
        "actual_vehicle_brand": vehicle.brand,
        "actual_vehicle_model": vehicle.model,
        "actual_vehicle_year": vehicle.year,
        "actual_vehicle_max_weight_kg": vehicle.max_weight_kg,
        "actual_vehicle_max_volume_m3": vehicle.max_volume_m3,
    }


def record_pricing_snapshot(
    db: Session,
    freight: FreightRequest,
    *,
    snapshot_type: str,
    pricing_type: str = "automatic",
    pricing_components: dict | None = None,
    final_customer_price: float | None = None,
    captured_at: datetime | None = None,
) -> FreightPricingSnapshot:
    """Append a point-in-time record. Existing snapshots are never mutated."""
    components = pricing_components or {}
    final_price = (
        final_customer_price
        if final_customer_price is not None
        else getattr(freight, "final_price", None)
    )
    estimated_price = getattr(freight, "estimated_price", None)
    actual_vehicle = _vehicle_snapshot(freight)
    actual_duration = _duration_minutes(
        getattr(freight, "trip_started_at", None)
        or getattr(freight, "started_at", None),
        getattr(freight, "trip_completed_at", None)
        or getattr(freight, "completed_at", None),
    )
    snapshot = FreightPricingSnapshot(
        freight_id=freight.id,
        snapshot_type=snapshot_type,
        pricing_version=components.get(
            "pricing_version",
            getattr(freight, "pricing_version", None) or PRICING_VERSION,
        ),
        pricing_type=components.get(
            "pricing_type",
            getattr(freight, "pricing_type", None) or pricing_type,
        ),
        captured_at=_as_utc(captured_at) if captured_at else datetime.now(timezone.utc),
        estimated_customer_price=estimated_price,
        accepted_customer_price=(
            getattr(freight, "client_pays", None)
            if getattr(freight, "customer_confirmed_at", None)
            else None
        ),
        final_customer_price=final_price,
        estimated_driver_earnings=getattr(freight, "driver_receives", None),
        final_driver_earnings=(
            getattr(freight, "driver_receives", None) if final_price is not None else None
        ),
        estimated_platform_fee=getattr(freight, "platform_fee", None),
        final_platform_fee=(
            getattr(freight, "platform_fee", None) if final_price is not None else None
        ),
        gross_price=getattr(freight, "client_pays", None),
        discount_amount=0,
        price_adjustment_amount=(
            round(final_price - estimated_price, 2)
            if final_price is not None and estimated_price is not None
            else None
        ),
        base_fare=components.get("base_fare"),
        distance_charge=components.get("distance_charge"),
        weight_charge=components.get("weight_charge"),
        time_charge=components.get("time_charge", 0),
        extras_charge=components.get(
            "extras_charge", getattr(freight, "helpers_cost", None)
        ),
        estimated_tolls=components.get("estimated_tolls", 0),
        urgency_charge=components.get("urgency_charge", 0),
        helper_charge=components.get(
            "helper_charge", getattr(freight, "helpers_cost", None)
        ),
        tax_amount=components.get("tax_amount", 0),
        calculation_metadata=(components or None),
        estimated_distance_km=getattr(freight, "distance_km", None),
        actual_distance_km=getattr(freight, "actual_distance_km", None),
        estimated_duration_minutes=getattr(
            freight, "estimated_duration_minutes", None
        ),
        actual_duration_minutes=actual_duration,
        recommended_vehicle_type=getattr(freight, "recommended_vehicle_type", None),
        selected_vehicle_type=getattr(freight, "selected_vehicle_type", None),
        actual_vehicle_id=actual_vehicle.get("actual_vehicle_id"),
        actual_vehicle_type=actual_vehicle.get("actual_vehicle_type"),
        actual_vehicle_brand=actual_vehicle.get("actual_vehicle_brand"),
        actual_vehicle_model=actual_vehicle.get("actual_vehicle_model"),
        actual_vehicle_year=actual_vehicle.get("actual_vehicle_year"),
        actual_vehicle_max_weight_kg=actual_vehicle.get(
            "actual_vehicle_max_weight_kg"
        ),
        actual_vehicle_max_volume_m3=actual_vehicle.get(
            "actual_vehicle_max_volume_m3"
        ),
        service_type=normalize_service_type(getattr(freight, "service_type", None)),
        estimated_weight_kg=getattr(freight, "cargo_weight_kg", None),
        estimated_volume_m3=getattr(freight, "cargo_volume_m3", None),
        helpers_count=getattr(freight, "requires_helpers", None),
        extra_stops_count=getattr(freight, "extra_stops", 0),
        urgent=getattr(freight, "is_urgent", None),
        pickup_commune=extract_commune(getattr(freight, "origin_address", None)),
        dropoff_commune=extract_commune(getattr(freight, "destination_address", None)),
        requested_at=getattr(freight, "requested_at", None)
        or getattr(freight, "created_at", None),
        price_estimated_at=getattr(freight, "price_estimated_at", None),
        customer_confirmed_at=getattr(freight, "customer_confirmed_at", None),
        driver_assigned_at=getattr(freight, "driver_assigned_at", None),
        driver_accepted_at=getattr(freight, "driver_accepted_at", None)
        or getattr(freight, "accepted_at", None),
        driver_arrived_pickup_at=getattr(freight, "driver_arrived_pickup_at", None),
        trip_started_at=getattr(freight, "trip_started_at", None)
        or getattr(freight, "started_at", None),
        driver_arrived_destination_at=getattr(
            freight, "driver_arrived_destination_at", None
        ),
        trip_completed_at=getattr(freight, "trip_completed_at", None)
        or getattr(freight, "completed_at", None),
        cancelled_at=getattr(freight, "cancelled_at", None),
    )
    db.add(snapshot)
    return snapshot
