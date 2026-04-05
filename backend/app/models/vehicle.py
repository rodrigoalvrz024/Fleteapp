from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Enum
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

class Vehicle(Base):
    __tablename__ = "vehicles"

    id = Column(Integer, primary_key=True, index=True)
    driver_id = Column(Integer, ForeignKey("drivers.id"), unique=True, nullable=False)
    type = Column(Enum(VehicleType), nullable=False)
    brand = Column(String, nullable=False)
    model = Column(String, nullable=False)
    year = Column(Integer, nullable=False)
    plate = Column(String, unique=True, nullable=False)
    color = Column(String, nullable=False)
    max_weight_kg = Column(Float, nullable=False)
    max_volume_m3 = Column(Float, nullable=True)
    photo_url = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    driver = relationship("Driver", back_populates="vehicle")