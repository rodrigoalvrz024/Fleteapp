from sqlalchemy import Column, Integer, String, Boolean, Float, ForeignKey, DateTime, Enum
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum
from app.database import Base

class DriverStatus(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    suspended = "suspended"

class Driver(Base):
    __tablename__ = "drivers"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True, nullable=False)
    rut = Column(String, unique=True, nullable=False)
    license_number = Column(String, nullable=False)
    license_expiry = Column(DateTime, nullable=False)
    status = Column(Enum(DriverStatus), default=DriverStatus.pending)
    is_available = Column(Boolean, default=False)
    rating_average = Column(Float, default=0.0)
    rating_count = Column(Integer, default=0)
    total_trips = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", foreign_keys=[user_id])
    vehicle = relationship("Vehicle", back_populates="driver", uselist=False)
    freight_requests = relationship("FreightRequest", back_populates="driver", foreign_keys="FreightRequest.driver_id")