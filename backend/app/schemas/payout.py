from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator

from app.models.driver_payout import DriverPayoutStatus


class DriverPayoutUpdate(BaseModel):
    status: DriverPayoutStatus
    scheduled_for: Optional[datetime] = None
    transfer_reference: Optional[str] = None
    note: Optional[str] = None

    @field_validator("transfer_reference", "note")
    def trim_text(cls, value):
        return value.strip() if value else value


class DriverPayoutResponse(BaseModel):
    id: int
    payment_id: int
    freight_id: int
    driver_id: int
    driver_name: str
    amount: float
    status: DriverPayoutStatus
    scheduled_for: Optional[datetime]
    paid_at: Optional[datetime]
    transfer_reference: Optional[str]
    note: Optional[str]
    created_at: datetime
    updated_at: Optional[datetime]

    class Config:
        from_attributes = True
