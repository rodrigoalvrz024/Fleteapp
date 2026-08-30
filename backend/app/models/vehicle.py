from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Enum, JSON
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum
from app.database import Base

class VehicleType(str, enum.Enum):
    pickup = "pickup"
    van = "van"
    truck_small = "truck_small"
    truck_medium = "truck_medium"
    truck_large = "truck_large"


class VehicleApprovalStatus(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"

class Vehicle(Base):
    __tablename__ = "vehicles"

    id = Column(Integer, primary_key=True, index=True)
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=False, index=True)
    type = Column(Enum(VehicleType), nullable=False)
    catalog_id = Column(String(80), nullable=True, index=True)
    brand = Column(String, nullable=False)
    model = Column(String, nullable=False)
    year = Column(Integer, nullable=False)
    plate = Column(String, unique=True, nullable=False)
    color = Column(String, nullable=False)
    max_weight_kg = Column(Float, nullable=False)
    max_volume_m3 = Column(Float, nullable=True)
    photo_url = Column(String, nullable=True)
    approval_status = Column(String(16), nullable=False, default=VehicleApprovalStatus.pending.value)
    approval_reason = Column(String(500), nullable=True)
    reviewed_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    supported_service_types = Column(JSON, nullable=False, default=list)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    last_modified_by = Column(Integer, nullable=True)

    driver = relationship("Driver", back_populates="vehicles")
