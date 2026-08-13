"""Freight domain helpers kept for backwards-compatible imports.

Pricing lives in :mod:`app.services.pricing_service`; state transitions belong
to the freight domain and remain here.
"""

import math

from app.models.freight import FreightStatus
from app.services.pricing_service import (
    PRICING_VERSION,
    PricingInputError,
    PricingService,
    estimate_price,
    normalize_service_type,
    recommend_vehicle_type,
)

__all__ = (
    "PRICING_VERSION",
    "PricingInputError",
    "PricingService",
    "calculate_distance_km",
    "can_transition",
    "estimate_price",
    "normalize_service_type",
    "recommend_vehicle_type",
)


def calculate_distance_km(
    lat1: float,
    lng1: float,
    lat2: float,
    lng2: float,
) -> float:
    """Legacy geometric helper. Automatic prices use a road route instead."""
    radius_km = 6371
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lng2 - lng1)
    a = (
        math.sin(delta_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    )
    return radius_km * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


VALID_TRANSITIONS = {
    FreightStatus.pending: [FreightStatus.accepted, FreightStatus.cancelled],
    FreightStatus.accepted: [FreightStatus.in_progress, FreightStatus.cancelled],
    FreightStatus.in_progress: [FreightStatus.completed, FreightStatus.cancelled],
    FreightStatus.completed: [],
    FreightStatus.cancelled: [],
}


def can_transition(current: FreightStatus, new: FreightStatus) -> bool:
    return new in VALID_TRANSITIONS.get(current, [])
