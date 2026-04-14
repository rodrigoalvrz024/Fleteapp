import math
from datetime import datetime
from app.models.freight import FreightStatus

# ── Tarifas base ───────────────────────────────────────────
BASE_RATE_PER_KM  = 800    # CLP por km
BASE_RATE_PER_KG  = 50     # CLP por kg
HELPER_COST       = 10000  # CLP por peoneta adicional

# ── Mínimos por modo ───────────────────────────────────────
MINIMUM_SCHEDULED = 20000  # Modo programado
MINIMUM_URGENT_DAY   = 30000  # Urgente 08:00 - 21:00
MINIMUM_URGENT_NIGHT = 40000  # Urgente 21:00 - 08:00

# ── Comisión plataforma ────────────────────────────────────
PLATFORM_FEE_PCT  = 0.15   # 15% total
CLIENT_FEE_PCT    = 0.075  # 7,5% al cliente
DRIVER_FEE_PCT    = 0.075  # 7,5% al conductor

def calculate_distance_km(
    lat1: float, lng1: float,
    lat2: float, lng2: float
) -> float:
    R = 6371
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi    = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

def get_urgent_minimum(scheduled_at: datetime = None) -> int:
    """Retorna el mínimo urgente según la hora."""
    now = scheduled_at or datetime.utcnow()
    # Chile es UTC-3 o UTC-4 según época
    # Usamos hora local del request
    hour = now.hour
    if 8 <= hour < 21:
        return MINIMUM_URGENT_DAY
    return MINIMUM_URGENT_NIGHT

def estimate_price(
    distance_km: float,
    weight_kg: float,
    helpers: int = 0,
    is_urgent: bool = False,
    scheduled_at: datetime = None
) -> dict:
    """
    Calcula el precio del flete con comisión dividida.
    
    Retorna:
        base_price:     precio calculado sin comisión
        client_pays:    lo que paga el cliente (base + 7,5%)
        driver_receives: lo que recibe el conductor (base - 7,5%)
        platform_fee:   ganancia de la plataforma (15% del base)
        minimum_applied: el mínimo que se aplicó
        mode:           'scheduled' o 'urgent'
    """
    # 1. Calcular precio base por distancia + peso
    calculated = (distance_km * BASE_RATE_PER_KM) + \
                 (weight_kg   * BASE_RATE_PER_KG)

    # 2. Aplicar mínimo según modo
    if is_urgent:
        minimum = get_urgent_minimum(scheduled_at)
        mode = "urgent"
    else:
        minimum = MINIMUM_SCHEDULED
        mode = "scheduled"

    base_price = max(round(calculated / 100) * 100, minimum)

    # 3. Agregar peonetas DESPUÉS de aplicar el mínimo
    helpers_cost = helpers * HELPER_COST
    base_price += helpers_cost

    # 4. Calcular comisión dividida
    platform_fee    = round(base_price * PLATFORM_FEE_PCT / 100) * 100
    client_surcharge  = round(base_price * CLIENT_FEE_PCT / 100) * 100
    driver_deduction  = round(base_price * DRIVER_FEE_PCT / 100) * 100

    client_pays      = base_price + client_surcharge
    driver_receives  = base_price - driver_deduction

    return {
        "base_price":      base_price,
        "client_pays":     client_pays,
        "driver_receives": driver_receives,
        "platform_fee":    platform_fee,
        "helpers_cost":    helpers_cost,
        "minimum_applied": minimum,
        "mode":            mode,
    }

# ── Transiciones de estado válidas ─────────────────────────
VALID_TRANSITIONS = {
    FreightStatus.pending:     [FreightStatus.accepted, FreightStatus.cancelled],
    FreightStatus.accepted:    [FreightStatus.in_progress, FreightStatus.cancelled],
    FreightStatus.in_progress: [FreightStatus.completed, FreightStatus.cancelled],
    FreightStatus.completed:   [],
    FreightStatus.cancelled:   [],
}

def can_transition(current: FreightStatus, new: FreightStatus) -> bool:
    return new in VALID_TRANSITIONS.get(current, [])