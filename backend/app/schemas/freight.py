from pydantic import BaseModel, field_validator
from typing import Optional, List
from datetime import datetime
from app.models.freight import FreightStatus

class FreightCreate(BaseModel):
    origin_address: str
    origin_lat: float
    origin_lng: float
    destination_address: str
    destination_lat: float
    destination_lng: float
    cargo_description: str
    cargo_weight_kg: float
    cargo_volume_m3: Optional[float] = None
    requires_helpers: int = 0
    scheduled_at: Optional[datetime] = None

    @field_validator("cargo_weight_kg")
    def weight_positive(cls, v):
        if v <= 0:
            raise ValueError("El peso debe ser mayor a 0")
        return v

class FreightStatusUpdate(BaseModel):
    status: FreightStatus
    note: Optional[str] = None

class StatusHistoryResponse(BaseModel):
    status: FreightStatus
    note: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True

    class FreightResponse(BaseModel):
        id:               int
        client_id:        int
        driver_id:        Optional[int]
        origin_address:   str
        destination_address: str
        distance_km:      Optional[float]
        cargo_description: str
        cargo_weight_kg:  float
        requires_helpers: int
        is_urgent:        bool
        mode:             str
        base_price:       Optional[float]
        client_pays:      Optional[float]
        driver_receives:  Optional[float]
        platform_fee:     Optional[float]
        helpers_cost:     Optional[float]
        estimated_price:  Optional[float]  # mantener por compatibilidad
        final_price:      Optional[float]
        status:           FreightStatus
        scheduled_at:     Optional[datetime]
        created_at:       datetime
        status_history:   List[StatusHistoryResponse] = []

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
        is_urgent:           bool = False  # ← nuevo

    @field_validator("cargo_weight_kg")
    def weight_positive(cls, v):
        if v <= 0:
            raise ValueError("El peso debe ser mayor a 0")
        return v