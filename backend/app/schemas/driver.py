import re
from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, computed_field, field_validator

from app.models.driver import DriverStatus
from app.models.vehicle import VehicleType
from app.services.driver_operational_service import build_driver_operational_blockers


def _normalize_rut(value: str) -> str:
    compact = re.sub(r"[^0-9kK]", "", value)
    if not re.fullmatch(r"[0-9]{7,8}[0-9kK]", compact):
        raise ValueError("RUT invalido")
    body, verifier = compact[:-1], compact[-1].upper()
    total = sum(
        int(digit) * (2 + (index % 6))
        for index, digit in enumerate(reversed(body))
    )
    remainder = 11 - (total % 11)
    expected = "0" if remainder == 11 else "K" if remainder == 10 else str(remainder)
    if verifier != expected:
        raise ValueError("RUT invalido")
    return f"{int(body):,}".replace(",", "") + f"-{verifier}"


def _future_document_date(value: datetime) -> datetime:
    comparison_now = datetime.now(value.tzinfo or timezone.utc)
    if value <= comparison_now:
        raise ValueError("La fecha de vencimiento debe estar en el futuro")
    return value


class DriverCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    rut: str
    license_number: str = Field(min_length=3, max_length=80)
    license_expiry: datetime

    @field_validator("rut")
    @classmethod
    def rut_format(cls, value: str) -> str:
        return _normalize_rut(value)

    @field_validator("license_expiry")
    @classmethod
    def license_not_expired(cls, value: datetime) -> datetime:
        return _future_document_date(value)


class DriverUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    is_available: Optional[bool] = None
    license_number: Optional[str] = Field(default=None, min_length=3, max_length=80)
    license_expiry: Optional[datetime] = None
    vehicle_doc_expiry: Optional[datetime] = None
    circulation_permit_expiry: Optional[datetime] = None
    technical_review_expiry: Optional[datetime] = None
    soap_expiry: Optional[datetime] = None

    @field_validator(
        "license_expiry",
        "vehicle_doc_expiry",
        "circulation_permit_expiry",
        "technical_review_expiry",
        "soap_expiry",
    )
    @classmethod
    def document_not_expired(cls, value: Optional[datetime]) -> Optional[datetime]:
        return _future_document_date(value) if value is not None else value


class VehicleCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    catalog_id: str = Field(min_length=3, max_length=80, pattern=r"^[a-z0-9-]+$")
    year: int = Field(ge=1900, le=datetime.now().year + 1)
    plate: str = Field(min_length=5, max_length=10)
    color: str = Field(min_length=2, max_length=40)
    max_weight_kg: float = Field(default=1000, gt=0, le=30_000, allow_inf_nan=False)
    max_volume_m3: Optional[float] = Field(
        default=None,
        gt=0,
        le=200,
        allow_inf_nan=False,
    )

    @field_validator("plate")
    @classmethod
    def normalize_plate(cls, value: str) -> str:
        normalized = re.sub(r"[^A-Za-z0-9]", "", value).upper()
        if len(normalized) < 5:
            raise ValueError("Patente invalida")
        return normalized


class VehicleResponse(BaseModel):
    id: int
    type: VehicleType
    catalog_id: Optional[str] = None
    brand: str
    model: str
    year: int
    plate: str
    color: str
    max_weight_kg: float
    max_volume_m3: Optional[float]
    photo_url: Optional[str]
    approval_status: str = "pending"
    approval_reason: Optional[str] = None
    reviewed_at: Optional[datetime] = None
    supported_service_types: list[str] = Field(default_factory=list)

    @field_validator("supported_service_types", mode="before")
    @classmethod
    def empty_supported_services_are_a_list(cls, value):
        return value or []

    class Config:
        from_attributes = True


class DriverResponse(BaseModel):
    id: int
    user_id: int
    rut: str
    license_number: str
    license_expiry: datetime
    status: DriverStatus
    is_available: bool
    profile_image_url: Optional[str] = None
    license_image_url: Optional[str] = None
    vehicle_doc_url: Optional[str] = None
    vehicle_doc_expiry: Optional[datetime] = None
    circulation_permit_url: Optional[str] = None
    circulation_permit_expiry: Optional[datetime] = None
    technical_review_url: Optional[str] = None
    technical_review_expiry: Optional[datetime] = None
    soap_url: Optional[str] = None
    soap_expiry: Optional[datetime] = None
    rejection_reason: Optional[str] = None
    submitted_at: Optional[datetime] = None
    documents_retention_until: Optional[datetime] = None
    documents_deleted_at: Optional[datetime] = None
    rating_average: float
    rating_count: int
    total_trips: int
    vehicle: Optional[VehicleResponse]
    vehicles: list[VehicleResponse] = Field(default_factory=list)

    @computed_field
    @property
    def operational_blockers(self) -> list[str]:
        return build_driver_operational_blockers(
            status=self.status,
            has_vehicle=any(
                vehicle.approval_status == "approved" for vehicle in self.vehicles
            ),
            license_image_url=self.license_image_url,
            license_expiry=self.license_expiry,
            vehicle_doc_url=self.vehicle_doc_url,
            vehicle_doc_expiry=self.vehicle_doc_expiry,
            circulation_permit_url=self.circulation_permit_url,
            circulation_permit_expiry=self.circulation_permit_expiry,
            technical_review_url=self.technical_review_url,
            technical_review_expiry=self.technical_review_expiry,
            soap_url=self.soap_url,
            soap_expiry=self.soap_expiry,
        )

    @computed_field
    @property
    def can_operate(self) -> bool:
        return len(self.operational_blockers) == 0

    class Config:
        from_attributes = True
