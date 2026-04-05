from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Enum
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum
from app.database import Base

class PaymentStatus(str, enum.Enum):
    pending = "pending"
    authorized = "authorized"
    failed = "failed"
    refunded = "refunded"

class PaymentMethod(str, enum.Enum):
    webpay = "webpay"
    cash = "cash"
    transfer = "transfer"

class Payment(Base):
    __tablename__ = "payments"

    id = Column(Integer, primary_key=True, index=True)
    freight_id = Column(Integer, ForeignKey("freight_requests.id"), unique=True, nullable=False)
    amount = Column(Float, nullable=False)
    method = Column(Enum(PaymentMethod), nullable=False)
    status = Column(Enum(PaymentStatus), default=PaymentStatus.pending)
    transaction_id = Column(String, nullable=True)
    buy_order = Column(String, nullable=True)
    webpay_token = Column(String, nullable=True)
    authorization_code = Column(String, nullable=True)
    paid_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    freight = relationship("FreightRequest", back_populates="payment")