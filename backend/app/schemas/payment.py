from pydantic import BaseModel, ConfigDict, Field
from typing import Optional
from datetime import datetime
from app.models.payment import PaymentStatus, PaymentMethod

class PaymentCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    freight_id: int = Field(gt=0)
    method: PaymentMethod

class PaymentResponse(BaseModel):
    id: int
    freight_id: int
    amount: float
    method: PaymentMethod
    status: PaymentStatus
    transaction_id: Optional[str]
    paid_at: Optional[datetime]
    created_at: datetime

    class Config:
        from_attributes = True

class WebpayInitResponse(BaseModel):
    token: str
    url: str
    redirect_url: str
