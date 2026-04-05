from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from app.models.payment import PaymentStatus, PaymentMethod

class PaymentCreate(BaseModel):
    freight_id: int
    method: PaymentMethod

class PaymentResponse(BaseModel):
    id: int
    freight_id: int
    amount: float
    method: PaymentMethod
    status: PaymentStatus
    transaction_id: Optional[str]
    webpay_token: Optional[str]
    paid_at: Optional[datetime]
    created_at: datetime

    class Config:
        from_attributes = True

class WebpayInitResponse(BaseModel):
    token: str
    url: str