from pydantic import BaseModel, field_validator
from typing import Optional, List
from datetime import datetime
from app.models.freight import FreightStatus


class StatusHistoryResponse(BaseModel):
    status:     FreightStatus
    note:       Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class FreightCreate(BaseModel):
    origin_address:      str
    origin_lat:          float
    origin_lng:          float
    destination_address: str
    destination_lat:     float
    destination_lng:     float
    cargo_description:   str
    cargo_weight_kg:     float
    cargo_volume_m3:     Optional[float] = None
    requires_helpers:    int = 0
    scheduled_at:        Optional[datetime] = None
    is_urgent:           bool = False

    @field_validator("cargo_weight_kg")
    def weight_positive(cls, v):
        if v <= 0:
            raise ValueError("El peso debe ser mayor a 0")
        return v


class FreightStatusUpdate(BaseModel):
    status: FreightStatus
    note:   Optional[str] = None


class FreightResponse(BaseModel):
    id:                  int
    client_id:           int
    driver_id:           Optional[int]
    origin_address:      str
    destination_address: str
    origin_lat:          Optional[float]
    origin_lng:          Optional[float]
    destination_lat:     Optional[float]
    destination_lng:     Optional[float]
    distance_km:         Optional[float]
    cargo_description:   str
    cargo_weight_kg:     float
    requires_helpers:    int
    is_urgent:           bool = False
    mode:                Optional[str] = "scheduled"
    base_price:          Optional[float]
    client_pays:         Optional[float]
    driver_receives:     Optional[float]
    platform_fee:        Optional[float]
    helpers_cost:        Optional[float]
    estimated_price:     Optional[float]
    final_price:         Optional[float]
    status:              FreightStatus
    scheduled_at:        Optional[datetime]
    created_at:          datetime
    status_history:      List[StatusHistoryResponse] = []

    class Config:
        from_attributes = True