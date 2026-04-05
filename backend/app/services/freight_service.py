import math
from app.models.freight import FreightStatus

BASE_RATE_PER_KM = 800        # CLP por km
BASE_RATE_PER_KG = 50         # CLP por kg
HELPER_COST = 5000            # CLP por ayudante
MINIMUM_PRICE = 8000          # CLP mínimo
CANCELLATION_WINDOW_MINUTES = 10

def calculate_distance_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def estimate_price(distance_km: float, weight_kg: float, helpers: int = 0) -> float:
    price = (distance_km * BASE_RATE_PER_KM) + (weight_kg * BASE_RATE_PER_KG) + (helpers * HELPER_COST)
    return max(round(price / 100) * 100, MINIMUM_PRICE)

VALID_TRANSITIONS = {
    FreightStatus.pending:     [FreightStatus.accepted, FreightStatus.cancelled],
    FreightStatus.accepted:    [FreightStatus.in_progress, FreightStatus.cancelled],
    FreightStatus.in_progress: [FreightStatus.completed, FreightStatus.cancelled],
    FreightStatus.completed:   [],
    FreightStatus.cancelled:   [],
}

def can_transition(current: FreightStatus, new: FreightStatus) -> bool:
    return new in VALID_TRANSITIONS.get(current, [])