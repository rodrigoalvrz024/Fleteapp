from pydantic import BaseModel, computed_field
from typing import Optional
from datetime import datetime
from app.models.driver import DriverStatus
from app.models.vehicle import VehicleType
from app.services.driver_operational_service import build_driver_operational_blockers

class DriverCreate(BaseModel):
    rut: str
    license_number: str
    license_expiry: datetime

class DriverUpdate(BaseModel):
    is_available: Optional[bool] = None
    license_number: Optional[str] = None
    license_expiry: Optional[datetime] = None
    vehicle_doc_expiry: Optional[datetime] = None
    circulation_permit_expiry: Optional[datetime] = None
    technical_review_expiry: Optional[datetime] = None
    soap_expiry: Optional[datetime] = None

class VehicleCreate(BaseModel):
    type: VehicleType = VehicleType.pickup
    brand: str
    model: str
    year: int
    plate: str
    color: str
    max_weight_kg: float = 1000
    max_volume_m3: Optional[float] = None

class VehicleResponse(BaseModel):
    id: int
    type: VehicleType
    brand: str
    model: str
    year: int
    plate: str
    color: str
    max_weight_kg: float
    max_volume_m3: Optional[float]
    photo_url: Optional[str]

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

    @computed_field
    @property
    def operational_blockers(self) -> list[str]:
        return build_driver_operational_blockers(
            status=self.status,
            has_vehicle=self.vehicle is not None,
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
