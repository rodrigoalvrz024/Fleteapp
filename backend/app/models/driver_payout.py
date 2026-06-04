import enum

from sqlalchemy import Column, DateTime, Enum, Float, ForeignKey, Integer, String
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class DriverPayoutStatus(str, enum.Enum):
    pending = "pending"
    scheduled = "scheduled"
    paid = "paid"
    failed = "failed"


class DriverPayout(Base):
    __tablename__ = "driver_payouts"

    id = Column(Integer, primary_key=True, index=True)
    payment_id = Column(Integer, ForeignKey("payments.id"), unique=True, nullable=False)
    freight_id = Column(
        Integer,
        ForeignKey("freight_requests.id"),
        unique=True,
        nullable=False,
    )
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=False, index=True)
    amount = Column(Float, nullable=False)
    status = Column(
        Enum(DriverPayoutStatus),
        default=DriverPayoutStatus.pending,
        nullable=False,
        index=True,
    )
    scheduled_for = Column(DateTime(timezone=True), nullable=True)
    paid_at = Column(DateTime(timezone=True), nullable=True)
    transfer_reference = Column(String, nullable=True)
    note = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    last_modified_by = Column(Integer, nullable=True)

    payment = relationship("Payment", back_populates="driver_payout")
    freight = relationship("FreightRequest", back_populates="driver_payout")
    driver = relationship("Driver", back_populates="payouts")

    @property
    def driver_name(self) -> str:
        return self.driver.user.full_name if self.driver and self.driver.user else ""
