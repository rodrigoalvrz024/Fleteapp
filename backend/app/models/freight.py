from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Enum, Text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum
from app.database import Base

class FreightStatus(str, enum.Enum):
    pending = "pending"
    accepted = "accepted"
    in_progress = "in_progress"
    completed = "completed"
    cancelled = "cancelled"

class FreightRequest(Base):
    __tablename__ = "freight_requests"

    id = Column(Integer, primary_key=True, index=True)
    client_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=True)

    origin_address = Column(String, nullable=False)
    origin_lat = Column(Float, nullable=False)
    origin_lng = Column(Float, nullable=False)
    destination_address = Column(String, nullable=False)
    destination_lat = Column(Float, nullable=False)
    destination_lng = Column(Float, nullable=False)

    distance_km = Column(Float, nullable=True)
    cargo_description = Column(Text, nullable=False)
    cargo_weight_kg = Column(Float, nullable=False)
    cargo_volume_m3 = Column(Float, nullable=True)
    requires_helpers = Column(Integer, default=0)

    estimated_price = Column(Float, nullable=True)
    final_price = Column(Float, nullable=True)
    status = Column(Enum(FreightStatus), default=FreightStatus.pending)

    scheduled_at = Column(DateTime(timezone=True), nullable=True)
    accepted_at = Column(DateTime(timezone=True), nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    cancelled_at = Column(DateTime(timezone=True), nullable=True)
    cancel_reason = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    client = relationship("User", back_populates="freight_requests", foreign_keys=[client_id])
    driver = relationship("Driver", back_populates="freight_requests", foreign_keys=[driver_id])
    status_history = relationship("TripStatusHistory", back_populates="freight")
    payment = relationship("Payment", back_populates="freight", uselist=False)
    rating = relationship("Rating", back_populates="freight", uselist=False)


class TripStatusHistory(Base):
    __tablename__ = "trip_status_history"

    id = Column(Integer, primary_key=True, index=True)
    freight_id = Column(Integer, ForeignKey("freight_requests.id"), nullable=False)
    status = Column(Enum(FreightStatus), nullable=False)
    note = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    freight = relationship("FreightRequest", back_populates="status_history")