"""Backend-owned matching rules for vehicle, capacity, and service type."""

from __future__ import annotations

from app.models.vehicle import Vehicle, VehicleApprovalStatus


VEHICLE_ORDER = {
    "pickup": 1,
    "van": 2,
    "truck_small": 3,
    "truck_medium": 4,
    "truck_large": 5,
}

SERVICE_VEHICLE_TYPES = {
    "package": {"pickup", "van", "truck_small", "truck_medium", "truck_large"},
    "urgent": {"pickup", "van", "truck_small", "truck_medium", "truck_large"},
    "home_office": {"van", "truck_small", "truck_medium", "truck_large"},
    "moving": {"van", "truck_small", "truck_medium", "truck_large"},
}


def _value(value) -> str:
    return value.value if hasattr(value, "value") else str(value)


def default_service_types(vehicle_type: str) -> list[str]:
    return sorted(
        service_type
        for service_type, allowed_types in SERVICE_VEHICLE_TYPES.items()
        if vehicle_type in allowed_types
    )


def vehicle_is_approved(vehicle: Vehicle) -> bool:
    return (
        vehicle.deleted_at is None
        and _value(vehicle.approval_status) == VehicleApprovalStatus.approved.value
    )


def vehicle_supports_freight(vehicle: Vehicle, freight) -> bool:
    if not vehicle_is_approved(vehicle):
        return False

    vehicle_type = _value(vehicle.type)
    service_type = (getattr(freight, "service_type", None) or "package").strip()
    supported = set(vehicle.supported_service_types or default_service_types(vehicle_type))
    if service_type not in supported:
        return False

    allowed_types = SERVICE_VEHICLE_TYPES.get(service_type, set(VEHICLE_ORDER))
    if vehicle_type not in allowed_types:
        return False

    required_type = (
        getattr(freight, "selected_vehicle_type", None)
        or getattr(freight, "recommended_vehicle_type", None)
    )
    if required_type and VEHICLE_ORDER.get(vehicle_type, 0) < VEHICLE_ORDER.get(required_type, 0):
        return False

    if float(vehicle.max_weight_kg or 0) < float(getattr(freight, "cargo_weight_kg", 0) or 0):
        return False
    required_volume = getattr(freight, "cargo_volume_m3", None)
    if required_volume is not None and float(vehicle.max_volume_m3 or 0) < float(required_volume):
        return False
    return True


def compatible_vehicles(driver, freight) -> list[Vehicle]:
    return [
        vehicle
        for vehicle in driver.vehicles
        if vehicle_supports_freight(vehicle, freight)
    ]


def driver_matches_freight(driver, freight) -> bool:
    return bool(compatible_vehicles(driver, freight))
