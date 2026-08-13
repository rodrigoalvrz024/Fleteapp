from datetime import datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models.freight import FreightStatus


class StatusHistoryResponse(BaseModel):
    status: FreightStatus
    note: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class FreightCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    origin_address: str = Field(min_length=3, max_length=250)
    origin_lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    origin_lng: float = Field(ge=-180, le=180, allow_inf_nan=False)
    destination_address: str = Field(min_length=3, max_length=250)
    destination_lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    destination_lng: float = Field(ge=-180, le=180, allow_inf_nan=False)
    cargo_description: str = Field(min_length=2, max_length=1000)
    cargo_weight_kg: float = Field(gt=0, le=20_000, allow_inf_nan=False)
    cargo_volume_m3: Optional[float] = Field(
        default=None,
        gt=0,
        le=200,
        allow_inf_nan=False,
    )
    requires_helpers: int = Field(default=0, ge=0, le=2)
    extra_stops: int = Field(default=0, ge=0, le=3)
    pickup_floor: Optional[int] = Field(default=None, ge=0, le=60)
    delivery_floor: Optional[int] = Field(default=None, ge=0, le=60)
    pickup_has_elevator: bool = True
    delivery_has_elevator: bool = True
    service_type: Optional[
        Literal["package", "moving", "home_office", "urgent"]
    ] = None
    requested_vehicle_type: Optional[
        Literal["pickup", "van", "truck_small", "truck_medium", "truck_large"]
    ] = None
    scheduled_at: Optional[datetime] = None
    is_urgent: bool = False
    quote_id: Optional[str] = Field(default=None, min_length=32, max_length=64)

    @field_validator("origin_address", "destination_address", "cargo_description")
    @classmethod
    def reject_control_characters(cls, value: str) -> str:
        if any(ord(character) < 32 for character in value):
            raise ValueError("El texto contiene caracteres no validos")
        return value


class PricingEstimateRequest(FreightCreate):
    """The same safe pricing inputs used later to create a freight."""

    quote_id: None = None


class FreightStatusUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    status: FreightStatus
    note: Optional[str] = Field(default=None, max_length=500)
    confirmation_pin: Optional[str] = Field(
        default=None,
        min_length=4,
        max_length=4,
        pattern=r"^[0-9]{4}$",
    )


class FreightCreateResponse(BaseModel):
    id: int
    client_id: int
    driver_id: Optional[int]
    origin_address: str
    destination_address: str
    origin_lat: Optional[float]
    origin_lng: Optional[float]
    destination_lat: Optional[float]
    destination_lng: Optional[float]
    distance_km: Optional[float]
    cargo_description: str
    cargo_weight_kg: float
    cargo_volume_m3: Optional[float] = None
    requires_helpers: int
    extra_stops: int = 0
    recommended_vehicle_type: Optional[str] = None
    selected_vehicle_type: Optional[str] = None
    pricing_version: Optional[str] = None
    pricing_type: Optional[str] = "automatic"
    requires_manual_quote: bool = False
    is_urgent: bool = False
    mode: Optional[str] = "scheduled"
    base_price: Optional[float]
    client_pays: Optional[float]
    driver_receives: Optional[float]
    platform_fee: Optional[float]
    helpers_cost: Optional[float]
    estimated_price: Optional[float]
    final_price: Optional[float]
    status: FreightStatus
    scheduled_at: Optional[datetime]
    created_at: datetime
    has_pickup_photo: bool = False
    has_delivery_photo: bool = False
    delivery_pin_ready: bool = False
    delivery_pin_verified: bool = False

    class Config:
        from_attributes = True

    @field_validator("extra_stops", mode="before")
    @classmethod
    def default_extra_stops(cls, value):
        return 0 if value is None else value

    @field_validator("requires_manual_quote", mode="before")
    @classmethod
    def default_manual_quote_flag(cls, value):
        return False if value is None else value


class DeliveryPinResponse(BaseModel):
    pin: str
    generated_at: datetime


class EvidenceViewResponse(BaseModel):
    url: str
    expires_at: datetime


class FreightDriverVehicleSummary(BaseModel):
    type: Optional[str] = None
    brand: Optional[str] = None
    model: Optional[str] = None
    year: Optional[int] = None
    plate: Optional[str] = None
    color: Optional[str] = None


class FreightDriverSummary(BaseModel):
    id: int
    full_name: str
    rating_average: float = 0
    rating_count: int = 0
    total_trips: int = 0
    is_verified: bool = False
    profile_image_url: Optional[str] = None
    vehicle: Optional[FreightDriverVehicleSummary] = None


class FreightResponse(BaseModel):
    id: int
    client_id: int
    driver_id: Optional[int]
    origin_address: str
    destination_address: str
    origin_lat: Optional[float]
    origin_lng: Optional[float]
    destination_lat: Optional[float]
    destination_lng: Optional[float]
    distance_km: Optional[float]
    cargo_description: str
    cargo_weight_kg: float
    cargo_volume_m3: Optional[float] = None
    requires_helpers: int
    extra_stops: int = 0
    recommended_vehicle_type: Optional[str] = None
    selected_vehicle_type: Optional[str] = None
    pricing_version: Optional[str] = None
    pricing_type: Optional[str] = "automatic"
    requires_manual_quote: bool = False
    is_urgent: bool = False
    mode: Optional[str] = "scheduled"
    base_price: Optional[float]
    client_pays: Optional[float]
    driver_receives: Optional[float]
    platform_fee: Optional[float]
    helpers_cost: Optional[float]
    estimated_price: Optional[float]
    final_price: Optional[float]
    status: FreightStatus
    scheduled_at: Optional[datetime]
    created_at: datetime
    has_pickup_photo: bool = False
    has_delivery_photo: bool = False
    delivery_pin_ready: bool = False
    delivery_pin_verified: bool = False
    payment_id: Optional[int] = None
    payment_status: Optional[str] = None
    rating_score: Optional[float] = None
    rating_comment: Optional[str] = None
    driver_summary: Optional[FreightDriverSummary] = None
    status_history: List[StatusHistoryResponse] = []

    class Config:
        from_attributes = True

    @field_validator("extra_stops", mode="before")
    @classmethod
    def default_extra_stops(cls, value):
        return 0 if value is None else value

    @field_validator("requires_manual_quote", mode="before")
    @classmethod
    def default_manual_quote_flag(cls, value):
        return False if value is None else value
