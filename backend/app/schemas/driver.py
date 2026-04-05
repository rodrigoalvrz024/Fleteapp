from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from app.models.driver import DriverStatus
from app.models.vehicle import VehicleType

class DriverCreate(BaseModel):
    rut: str
    license_number: str
    license_expiry: datetime

class DriverUpdate(BaseModel):
    is_available: Optional[bool] = None
    license_number: Optional[str] = None
    license_expiry: Optional[datetime] = None

class VehicleCreate(BaseModel):
    type: VehicleType
    brand: str
    model: str
    year: int
    plate: str
    color: str
    max_weight_kg: float
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
    status: DriverStatus
    is_available: bool
    rating_average: float
    rating_count: int
    total_trips: int
    vehicle: Optional[VehicleResponse]

    class Config:
        from_attributes = True