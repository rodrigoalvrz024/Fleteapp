"""Deterministic and configurable freight pricing for Muvv.

The public API only supplies route and cargo inputs. This module owns every
financial calculation so that neither a mobile client nor a router can change
prices, vehicle constraints, or commission rules.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from decimal import Decimal, ROUND_CEILING
import json
import logging
from typing import Any
import unicodedata

from app.core.config import settings


logger = logging.getLogger(__name__)

PRICING_VERSION = "v2"
SUPPORTED_VEHICLE_TYPES = (
    "pickup",
    "van",
    "truck_small",
    "truck_medium",
    "truck_large",
)


class PricingInputError(ValueError):
    """Raised when an input cannot be priced by a deterministic rule."""


@dataclass(frozen=True)
class VehiclePricingConfig:
    vehicle_type: str
    display_name: str
    base_fare: int
    minimum_fare: int
    rate_per_km: int
    rate_per_minute: int
    included_weight_kg: int
    excess_weight_rate: int
    max_weight_kg: int
    max_volume_m3: float


@dataclass(frozen=True)
class PricingPolicy:
    helper_fee: int = 10_000
    extra_stop_fee: int = 2_500
    stairs_fee_per_floor: int = 1_000
    urgency_multiplier: Decimal = Decimal("1.15")
    demand_multiplier: Decimal = Decimal("1.00")
    client_service_fee_rate: Decimal = Decimal("0.075")
    driver_service_fee_rate: Decimal = Decimal("0.075")
    tax_rate: Decimal = Decimal("0.00")
    rounding_increment: int = 100


DEFAULT_VEHICLE_CONFIGS: dict[str, VehiclePricingConfig] = {
    "pickup": VehiclePricingConfig(
        vehicle_type="pickup",
        display_name="Camioneta",
        base_fare=10_000,
        minimum_fare=20_000,
        rate_per_km=800,
        rate_per_minute=120,
        included_weight_kg=100,
        excess_weight_rate=20,
        max_weight_kg=500,
        max_volume_m3=2.0,
    ),
    "van": VehiclePricingConfig(
        vehicle_type="van",
        display_name="Furgon",
        base_fare=13_000,
        minimum_fare=28_000,
        rate_per_km=1_050,
        rate_per_minute=180,
        included_weight_kg=250,
        excess_weight_rate=25,
        max_weight_kg=1_000,
        max_volume_m3=5.0,
    ),
    "truck_small": VehiclePricingConfig(
        vehicle_type="truck_small",
        display_name="Camion pequeno",
        base_fare=17_000,
        minimum_fare=35_000,
        rate_per_km=1_300,
        rate_per_minute=230,
        included_weight_kg=500,
        excess_weight_rate=30,
        max_weight_kg=2_000,
        max_volume_m3=10.0,
    ),
    "truck_medium": VehiclePricingConfig(
        vehicle_type="truck_medium",
        display_name="Camion mediano",
        base_fare=23_000,
        minimum_fare=45_000,
        rate_per_km=1_650,
        rate_per_minute=290,
        included_weight_kg=1_000,
        excess_weight_rate=35,
        max_weight_kg=4_000,
        max_volume_m3=20.0,
    ),
    "truck_large": VehiclePricingConfig(
        vehicle_type="truck_large",
        display_name="Camion grande",
        base_fare=32_000,
        minimum_fare=60_000,
        rate_per_km=2_000,
        rate_per_minute=360,
        included_weight_kg=2_000,
        excess_weight_rate=40,
        max_weight_kg=10_000,
        max_volume_m3=50.0,
    ),
}

_COMPLEX_CARGO_TERMS = (
    "mudanza completa",
    "piano",
    "caja fuerte",
    "maquinaria",
    "grua",
    "material peligroso",
    "material peligroso",
)


def normalize_service_type(value: str | None) -> str | None:
    """Map legacy labels to stable service categories without pricing by label."""
    if not value:
        return None
    normalized = "".join(
        character
        for character in unicodedata.normalize("NFD", value.strip().lower())
        if unicodedata.category(character) != "Mn"
    )
    aliases = {
        "package": "package",
        "paqueteria": "package",
        "moving": "moving",
        "mudanza": "moving",
        "home_office": "home_office",
        "hogar u oficina": "home_office",
        "urgent": "urgent",
        "envio urgente": "urgent",
    }
    return aliases.get(normalized)


def _decimal(value: int | float | Decimal) -> Decimal:
    return Decimal(str(value))


def _round_money(value: Decimal, increment: int) -> int:
    """Round monetary amounts up once, using the central policy increment."""
    if increment <= 0:
        raise PricingInputError("El incremento de redondeo debe ser positivo")
    rounded = (value / Decimal(increment)).to_integral_value(rounding=ROUND_CEILING)
    return int(rounded * Decimal(increment))


def _normalize_cargo_text(value: str | None) -> str:
    if not value:
        return ""
    return "".join(
        character
        for character in unicodedata.normalize("NFD", value.lower())
        if unicodedata.category(character) != "Mn"
    )


def _policy_from_environment() -> PricingPolicy:
    """Allow calibrated policy values via one backend-only JSON environment value."""
    raw = settings.PRICING_CONFIG_JSON.strip()
    if not raw:
        return PricingPolicy()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        logger.error("PRICING_CONFIG_JSON is invalid; using default pricing policy")
        return PricingPolicy()
    if not isinstance(data, dict):
        logger.error("PRICING_CONFIG_JSON must contain an object; using defaults")
        return PricingPolicy()
    policy_data = data.get("policy", {})
    if not isinstance(policy_data, dict):
        policy_data = {}
    allowed = set(PricingPolicy.__dataclass_fields__)
    clean = {key: value for key, value in policy_data.items() if key in allowed}
    for name in (
        "urgency_multiplier",
        "demand_multiplier",
        "client_service_fee_rate",
        "driver_service_fee_rate",
        "tax_rate",
    ):
        if name in clean:
            clean[name] = Decimal(str(clean[name]))
    try:
        return PricingPolicy(**clean)
    except (TypeError, ValueError):
        logger.error("PRICING_CONFIG_JSON policy is invalid; using defaults")
        return PricingPolicy()


def _vehicle_configs_from_environment() -> dict[str, VehiclePricingConfig]:
    configs = dict(DEFAULT_VEHICLE_CONFIGS)
    raw = settings.PRICING_CONFIG_JSON.strip()
    if not raw:
        return configs
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return configs
    vehicle_data = data.get("vehicles", {}) if isinstance(data, dict) else {}
    if not isinstance(vehicle_data, dict):
        return configs
    allowed = set(VehiclePricingConfig.__dataclass_fields__)
    for vehicle_type, changes in vehicle_data.items():
        if vehicle_type not in configs or not isinstance(changes, dict):
            continue
        base = asdict(configs[vehicle_type])
        base.update({key: value for key, value in changes.items() if key in allowed})
        base["vehicle_type"] = vehicle_type
        try:
            configs[vehicle_type] = VehiclePricingConfig(**base)
        except (TypeError, ValueError):
            logger.error("Invalid pricing config for vehicle_type=%s", vehicle_type)
    return configs


class PricingService:
    """Calculates a transparent automatic price from backend route data only."""

    def __init__(
        self,
        *,
        vehicle_configs: dict[str, VehiclePricingConfig] | None = None,
        policy: PricingPolicy | None = None,
    ) -> None:
        self.vehicle_configs = vehicle_configs or _vehicle_configs_from_environment()
        self.policy = policy or _policy_from_environment()

    def recommend_vehicle_type(
        self,
        *,
        weight_kg: float,
        volume_m3: float | None = None,
    ) -> str | None:
        if weight_kg <= 0:
            raise PricingInputError("El peso debe ser mayor que cero")
        volume = volume_m3 or 0.0
        for vehicle_type in SUPPORTED_VEHICLE_TYPES:
            config = self.vehicle_configs[vehicle_type]
            if weight_kg <= config.max_weight_kg and volume <= config.max_volume_m3:
                return vehicle_type
        return None

    def _manual_quote_reason(
        self,
        *,
        cargo_description: str | None,
        weight_kg: float,
        volume_m3: float | None,
        service_type: str | None,
    ) -> str | None:
        if self.recommend_vehicle_type(weight_kg=weight_kg, volume_m3=volume_m3) is None:
            return "cargo_outside_supported_capacity"
        text = _normalize_cargo_text(cargo_description)
        if any(term in text for term in _COMPLEX_CARGO_TERMS):
            return "special_cargo"
        if service_type == "moving" and (volume_m3 or 0) >= 20:
            return "large_moving_service"
        return None

    def estimate(
        self,
        *,
        distance_km: float,
        duration_minutes: float,
        weight_kg: float,
        volume_m3: float | None = None,
        helpers: int = 0,
        extra_stops: int = 0,
        pickup_floor: int | None = None,
        delivery_floor: int | None = None,
        pickup_has_elevator: bool = True,
        delivery_has_elevator: bool = True,
        estimated_tolls: int | float = 0,
        is_urgent: bool = False,
        service_type: str | None = None,
        cargo_description: str | None = None,
        requested_vehicle_type: str | None = None,
    ) -> dict[str, Any]:
        if distance_km <= 0 or duration_minutes <= 0:
            raise PricingInputError("La ruta debe incluir distancia y duracion validas")
        if weight_kg <= 0:
            raise PricingInputError("El peso debe ser mayor que cero")
        if helpers < 0 or helpers > 2:
            raise PricingInputError("Solo se permiten entre 0 y 2 ayudantes")
        if extra_stops < 0 or extra_stops > 3:
            raise PricingInputError("Solo se permiten entre 0 y 3 paradas adicionales")
        if estimated_tolls < 0:
            raise PricingInputError("Los peajes no pueden ser negativos")

        normalized_service = normalize_service_type(service_type)
        reason = self._manual_quote_reason(
            cargo_description=cargo_description,
            weight_kg=weight_kg,
            volume_m3=volume_m3,
            service_type=normalized_service,
        )
        recommended = self.recommend_vehicle_type(
            weight_kg=weight_kg,
            volume_m3=volume_m3,
        )
        if reason or not recommended:
            return {
                "pricing_version": PRICING_VERSION,
                "pricing_type": "manual_quote",
                "requires_manual_quote": True,
                "manual_quote_reason": reason or "unsupported_cargo",
                "recommended_vehicle_type": recommended,
                "recommended_vehicle_name": (
                    self.vehicle_configs[recommended].display_name if recommended else None
                ),
                "distance_km": round(distance_km, 2),
                "duration_minutes": round(duration_minutes, 1),
            }

        selected = requested_vehicle_type or recommended
        if selected not in self.vehicle_configs:
            raise PricingInputError("El tipo de vehiculo solicitado no esta disponible")
        if SUPPORTED_VEHICLE_TYPES.index(selected) < SUPPORTED_VEHICLE_TYPES.index(recommended):
            raise PricingInputError("El vehiculo solicitado no soporta esta carga")
        config = self.vehicle_configs[selected]
        if weight_kg > config.max_weight_kg or (volume_m3 or 0) > config.max_volume_m3:
            raise PricingInputError("El vehiculo solicitado no soporta esta carga")

        distance_charge = _decimal(distance_km) * _decimal(config.rate_per_km)
        time_charge = _decimal(duration_minutes) * _decimal(config.rate_per_minute)
        excess_weight = max(_decimal(weight_kg) - _decimal(config.included_weight_kg), Decimal("0"))
        weight_charge = excess_weight * _decimal(config.excess_weight_rate)
        transport_cost = _decimal(config.base_fare) + distance_charge + time_charge + weight_charge
        helper_charge = _decimal(helpers * self.policy.helper_fee)
        extra_stops_charge = _decimal(extra_stops * self.policy.extra_stop_fee)
        pickup_stairs = self._stairs_charge(pickup_floor, pickup_has_elevator)
        delivery_stairs = self._stairs_charge(delivery_floor, delivery_has_elevator)
        stairs_charge = pickup_stairs + delivery_stairs
        tolls = _decimal(estimated_tolls)
        extras_charge = helper_charge + extra_stops_charge + stairs_charge + tolls
        subtotal = transport_cost + extras_charge

        urgency_multiplier = self.policy.urgency_multiplier if is_urgent else Decimal("1")
        demand_multiplier = self.policy.demand_multiplier
        adjusted_price = subtotal * urgency_multiplier * demand_multiplier
        urgency_charge = adjusted_price - (subtotal * demand_multiplier)
        minimum_fare = _decimal(config.minimum_fare) * urgency_multiplier
        minimum_adjustment = max(minimum_fare - adjusted_price, Decimal("0"))
        gross_price = _round_money(
            max(adjusted_price, minimum_fare), self.policy.rounding_increment
        )

        client_surcharge = _round_money(
            _decimal(gross_price) * self.policy.client_service_fee_rate,
            self.policy.rounding_increment,
        )
        driver_deduction = _round_money(
            _decimal(gross_price) * self.policy.driver_service_fee_rate,
            self.policy.rounding_increment,
        )
        tax_amount = _round_money(
            _decimal(gross_price) * self.policy.tax_rate,
            self.policy.rounding_increment,
        ) if self.policy.tax_rate else 0
        customer_price = gross_price + client_surcharge + tax_amount
        driver_earnings = gross_price - driver_deduction
        platform_fee = customer_price - driver_earnings

        metadata = {
            "vehicle_pricing": asdict(config),
            "policy": self._serializable_policy(),
            "transport_cost": float(transport_cost),
            "subtotal": float(subtotal),
            "adjusted_price_before_rounding": float(adjusted_price),
            "requested_vehicle_type": requested_vehicle_type,
            "extra_stops_charge": float(extra_stops_charge),
            "stairs_charge": float(stairs_charge),
            "demand_multiplier": float(demand_multiplier),
        }
        return {
            "currency": "CLP",
            "pricing_version": PRICING_VERSION,
            "pricing_type": "automatic",
            "requires_manual_quote": False,
            "manual_quote_reason": None,
            "mode": "urgent" if is_urgent else "scheduled",
            "recommended_vehicle_type": recommended,
            "recommended_vehicle_name": self.vehicle_configs[recommended].display_name,
            "selected_vehicle_type": selected,
            "base_price": gross_price,
            "base_fare": config.base_fare,
            "distance_charge": _round_money(distance_charge, self.policy.rounding_increment),
            "time_charge": _round_money(time_charge, self.policy.rounding_increment),
            "weight_charge": _round_money(weight_charge, self.policy.rounding_increment),
            "helper_charge": int(helper_charge),
            "helpers_cost": int(helper_charge),
            "extra_stops_charge": int(extra_stops_charge),
            "stairs_charge": int(stairs_charge),
            "estimated_tolls": int(tolls),
            "extras_charge": int(extras_charge),
            "urgency_charge": _round_money(urgency_charge, self.policy.rounding_increment),
            "minimum_fare": _round_money(minimum_fare, self.policy.rounding_increment),
            "minimum_adjustment": _round_money(minimum_adjustment, self.policy.rounding_increment),
            "minimum_applied": minimum_adjustment > 0,
            "subtotal": _round_money(subtotal, self.policy.rounding_increment),
            "tax_amount": tax_amount,
            "client_surcharge": client_surcharge,
            "driver_deduction": driver_deduction,
            "client_pays": customer_price,
            "customer_price": customer_price,
            "driver_receives": driver_earnings,
            "driver_earnings": driver_earnings,
            "platform_fee": platform_fee,
            "distance_km": round(distance_km, 2),
            "duration_minutes": round(duration_minutes, 1),
            "calculation_metadata": metadata,
        }

    def _stairs_charge(self, floor: int | None, has_elevator: bool) -> Decimal:
        if floor is None or floor <= 1 or has_elevator:
            return Decimal("0")
        return _decimal((floor - 1) * self.policy.stairs_fee_per_floor)

    def _serializable_policy(self) -> dict[str, int | float]:
        return {
            key: float(value) if isinstance(value, Decimal) else value
            for key, value in asdict(self.policy).items()
        }


def recommend_vehicle_type(weight_kg: float, volume_m3: float | None = None) -> str:
    """Compatibility helper for legacy callers that expect a vehicle type."""
    return PricingService().recommend_vehicle_type(
        weight_kg=weight_kg,
        volume_m3=volume_m3,
    ) or "truck_large"


def estimate_price(
    distance_km: float,
    weight_kg: float,
    helpers: int = 0,
    is_urgent: bool = False,
    scheduled_at: datetime | None = None,
    *,
    duration_minutes: float | None = None,
    volume_m3: float | None = None,
    service_type: str | None = None,
    cargo_description: str | None = None,
    extra_stops: int = 0,
    pickup_floor: int | None = None,
    delivery_floor: int | None = None,
    pickup_has_elevator: bool = True,
    delivery_has_elevator: bool = True,
    requested_vehicle_type: str | None = None,
    estimated_tolls: int | float = 0,
) -> dict[str, Any]:
    """Compatibility facade. New endpoints should use ``PricingService`` directly."""
    del scheduled_at  # Time windows are not priced until a calibrated rule exists.
    return PricingService().estimate(
        distance_km=distance_km,
        duration_minutes=duration_minutes or max(distance_km * 3, 1),
        weight_kg=weight_kg,
        volume_m3=volume_m3,
        helpers=helpers,
        extra_stops=extra_stops,
        pickup_floor=pickup_floor,
        delivery_floor=delivery_floor,
        pickup_has_elevator=pickup_has_elevator,
        delivery_has_elevator=delivery_has_elevator,
        estimated_tolls=estimated_tolls,
        is_urgent=is_urgent,
        service_type=service_type,
        cargo_description=cargo_description,
        requested_vehicle_type=requested_vehicle_type,
    )
