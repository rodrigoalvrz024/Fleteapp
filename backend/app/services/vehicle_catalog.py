"""Curated vehicle names used by the Muvv driver onboarding in Chile."""

from __future__ import annotations

from app.models.vehicle import VehicleType


def _item(catalog_id: str, brand: str, model: str, vehicle_type: VehicleType) -> dict:
    return {
        "catalog_id": catalog_id,
        "brand": brand,
        "model": model,
        "vehicle_type": vehicle_type.value,
    }


# This is intentionally a curated onboarding catalog, not a claim that it lists
# every vehicle sold in Chile. Adding a new model is a reviewed product change.
VEHICLE_CATALOG = [
    _item("chevrolet-nhr", "Chevrolet", "NHR", VehicleType.truck_small),
    _item("chevrolet-nkr", "Chevrolet", "NKR", VehicleType.truck_small),
    _item("chevrolet-npr", "Chevrolet", "NPR", VehicleType.truck_medium),
    _item("chevrolet-silverado-3500", "Chevrolet", "Silverado 3500", VehicleType.pickup),
    _item("citroen-berlingo", "Citroen", "Berlingo", VehicleType.van),
    _item("citroen-jumper", "Citroen", "Jumper", VehicleType.van),
    _item("fiat-ducato", "Fiat", "Ducato", VehicleType.van),
    _item("fiat-fiorino", "Fiat", "Fiorino", VehicleType.van),
    _item("ford-ranger", "Ford", "Ranger", VehicleType.pickup),
    _item("ford-transit", "Ford", "Transit", VehicleType.van),
    _item("ford-f350", "Ford", "F-350", VehicleType.truck_small),
    _item("foton-tm3", "Foton", "TM3", VehicleType.truck_small),
    _item("foton-tm5", "Foton", "TM5", VehicleType.truck_small),
    _item("foton-aumark-s", "Foton", "Aumark S", VehicleType.truck_medium),
    _item("hino-300", "Hino", "300", VehicleType.truck_small),
    _item("hino-500", "Hino", "500", VehicleType.truck_large),
    _item("hyundai-h100", "Hyundai", "H100", VehicleType.pickup),
    _item("hyundai-porter", "Hyundai", "Porter", VehicleType.pickup),
    _item("hyundai-hd65", "Hyundai", "HD65", VehicleType.truck_small),
    _item("hyundai-hd78", "Hyundai", "HD78", VehicleType.truck_medium),
    _item("isuzu-dmax", "Isuzu", "D-Max", VehicleType.pickup),
    _item("isuzu-npr", "Isuzu", "NPR", VehicleType.truck_medium),
    _item("isuzu-nqr", "Isuzu", "NQR", VehicleType.truck_medium),
    _item("jac-x200", "JAC", "X200", VehicleType.truck_small),
    _item("jac-x300", "JAC", "X300", VehicleType.truck_small),
    _item("jac-x500", "JAC", "X500", VehicleType.truck_medium),
    _item("jac-x700", "JAC", "X700", VehicleType.truck_large),
    _item("kia-bongo-k2500", "Kia", "Bongo K2500", VehicleType.pickup),
    _item("kia-frontier-k2500", "Kia", "Frontier K2500", VehicleType.pickup),
    _item("maxus-deliver-3", "Maxus", "Deliver 3", VehicleType.van),
    _item("maxus-deliver-9", "Maxus", "Deliver 9", VehicleType.van),
    _item("maxus-t60", "Maxus", "T60", VehicleType.pickup),
    _item("mercedes-sprinter", "Mercedes-Benz", "Sprinter", VehicleType.van),
    _item("mercedes-accelo-815", "Mercedes-Benz", "Accelo 815", VehicleType.truck_medium),
    _item("mercedes-atego-1726", "Mercedes-Benz", "Atego 1726", VehicleType.truck_large),
    _item("mitsubishi-l200", "Mitsubishi", "L200", VehicleType.pickup),
    _item("mitsubishi-canter", "Mitsubishi", "Canter", VehicleType.truck_small),
    _item("peugeot-partner", "Peugeot", "Partner", VehicleType.van),
    _item("peugeot-boxer", "Peugeot", "Boxer", VehicleType.van),
    _item("ram-700", "RAM", "700", VehicleType.pickup),
    _item("toyota-hilux", "Toyota", "Hilux", VehicleType.pickup),
    _item("volkswagen-amarok", "Volkswagen", "Amarok", VehicleType.pickup),
    _item("volkswagen-delivery-9170", "Volkswagen", "Delivery 9.170", VehicleType.truck_medium),
    _item("volkswagen-constellation-17280", "Volkswagen", "Constellation 17.280", VehicleType.truck_large),
]

_BY_ID = {entry["catalog_id"]: entry for entry in VEHICLE_CATALOG}


def list_vehicle_catalog() -> list[dict]:
    return sorted(VEHICLE_CATALOG, key=lambda item: (item["brand"], item["model"]))


def get_catalog_vehicle(catalog_id: str) -> dict | None:
    return _BY_ID.get(catalog_id)
