from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException

from app.models.driver import Driver, DriverStatus
from app.services.freight_matching_service import vehicle_is_approved


def _status_value(status: Any) -> str:
    return status.value if hasattr(status, "value") else str(status)


def build_driver_operational_blockers(
    *,
    status: Any,
    has_vehicle: bool,
    license_image_url: str | None,
    license_expiry: datetime | None,
    vehicle_doc_url: str | None,
    vehicle_doc_expiry: datetime | None,
    circulation_permit_url: str | None,
    circulation_permit_expiry: datetime | None,
    technical_review_url: str | None,
    technical_review_expiry: datetime | None,
    soap_url: str | None,
    soap_expiry: datetime | None,
) -> list[str]:
    today = datetime.now(timezone.utc).date()
    blockers: list[str] = []

    required_documents = [
        ("licencia", license_image_url, license_expiry),
        (
            "permiso de circulacion",
            circulation_permit_url or vehicle_doc_url,
            circulation_permit_expiry or vehicle_doc_expiry,
        ),
        ("revision tecnica", technical_review_url, technical_review_expiry),
        ("SOAP", soap_url, soap_expiry),
    ]

    for label, document_ref, expiry in required_documents:
        if not document_ref:
            blockers.append(f"Falta {label}")
            continue
        if not expiry:
            blockers.append(f"Falta vencimiento de {label}")
            continue
        if expiry.date() < today:
            blockers.append(f"{label} vencido")

    if not has_vehicle:
        blockers.append("Falta vehiculo")
    if _status_value(status) != DriverStatus.approved.value:
        blockers.append("Conductor no aprobado")

    return blockers


def driver_operational_blockers(driver: Driver) -> list[str]:
    return build_driver_operational_blockers(
        status=driver.status,
        has_vehicle=any(vehicle_is_approved(vehicle) for vehicle in driver.vehicles),
        license_image_url=driver.license_image_url,
        license_expiry=driver.license_expiry,
        vehicle_doc_url=driver.vehicle_doc_url,
        vehicle_doc_expiry=driver.vehicle_doc_expiry,
        circulation_permit_url=driver.circulation_permit_url,
        circulation_permit_expiry=driver.circulation_permit_expiry,
        technical_review_url=driver.technical_review_url,
        technical_review_expiry=driver.technical_review_expiry,
        soap_url=driver.soap_url,
        soap_expiry=driver.soap_expiry,
    )


def require_driver_can_operate(driver: Driver) -> None:
    blockers = driver_operational_blockers(driver)
    if blockers:
        raise HTTPException(
            status_code=403,
            detail={
                "message": "No puedes operar hasta resolver tus documentos",
                "blockers": blockers,
            },
        )
