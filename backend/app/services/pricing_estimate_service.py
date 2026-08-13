"""Coordinates real routing and deterministic freight pricing."""

from __future__ import annotations

import logging
from time import perf_counter
from typing import Any

from app.services.maps_service import get_distance_and_duration
from app.services.pricing_service import PricingService


logger = logging.getLogger(__name__)


async def calculate_pricing_estimate(
    data: Any,
    *,
    request_id: str | None = None,
) -> tuple[dict, dict]:
    """Return route metadata and the backend-owned price breakdown.

    Request logs deliberately contain no address, coordinates, customer ID, or
    cargo description. Those details already live in the protected freight.
    """
    started = perf_counter()
    route = await get_distance_and_duration(
        data.origin_lat,
        data.origin_lng,
        data.destination_lat,
        data.destination_lng,
    )
    price = PricingService().estimate(
        distance_km=route["distance_km"],
        duration_minutes=route["duration_minutes"],
        weight_kg=data.cargo_weight_kg,
        volume_m3=data.cargo_volume_m3,
        helpers=data.requires_helpers,
        extra_stops=data.extra_stops,
        pickup_floor=data.pickup_floor,
        delivery_floor=data.delivery_floor,
        pickup_has_elevator=data.pickup_has_elevator,
        delivery_has_elevator=data.delivery_has_elevator,
        is_urgent=data.is_urgent,
        service_type=data.service_type,
        cargo_description=data.cargo_description,
        requested_vehicle_type=data.requested_vehicle_type,
    )
    logger.info(
        "pricing_estimate request_id=%s route_provider=%s vehicle=%s pricing_type=%s latency_ms=%d",
        request_id or "unknown",
        route.get("provider"),
        price.get("selected_vehicle_type") or price.get("recommended_vehicle_type"),
        price.get("pricing_type"),
        (perf_counter() - started) * 1000,
    )
    return route, price
