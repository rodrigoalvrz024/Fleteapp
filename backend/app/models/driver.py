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
    profile_image_url = Column(String, nullable=True)
    license_image_url = Column(String, nullable=True)
    vehicle_doc_url = Column(String, nullable=True)
    vehicle_doc_expiry = Column(DateTime(timezone=True), nullable=True)
    circulation_permit_url = Column(String, nullable=True)
    circulation_permit_expiry = Column(DateTime(timezone=True), nullable=True)
    technical_review_url = Column(String, nullable=True)
    technical_review_expiry = Column(DateTime(timezone=True), nullable=True)
    soap_url = Column(String, nullable=True)
    soap_expiry = Column(DateTime(timezone=True), nullable=True)
    rejection_reason = Column(String, nullable=True)
    submitted_at = Column(DateTime(timezone=True), nullable=True)
    documents_retention_until = Column(DateTime(timezone=True), nullable=True)
    documents_deleted_at = Column(DateTime(timezone=True), nullable=True)
    status = Column(Enum(DriverStatus), default=DriverStatus.pending)
    is_available = Column(Boolean, default=False)
    rating_average = Column(Float, default=0.0)
    rating_count = Column(Integer, default=0)
    total_trips = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    last_modified_by = Column(Integer, nullable=True)

    user = relationship("User", foreign_keys=[user_id])
    vehicles = relationship(
        "Vehicle",
        back_populates="driver",
        order_by="Vehicle.created_at",
    )
    freight_requests = relationship("FreightRequest", back_populates="driver", foreign_keys="FreightRequest.driver_id")
    review_audits = relationship("DriverReviewAudit", back_populates="driver")
    payouts = relationship("DriverPayout", back_populates="driver")

    @property
    def vehicle(self):
        """Legacy primary vehicle, preferring an approved active vehicle."""
        active = [vehicle for vehicle in self.vehicles if vehicle.deleted_at is None]
        return next(
            (vehicle for vehicle in active if vehicle.approval_status == "approved"),
            active[0] if active else None,
        )

    @vehicle.setter
    def vehicle(self, value):
        """Compatibility bridge for code written before multi-vehicle support."""
        if value is None:
            self.vehicles.clear()
            return
        if value not in self.vehicles:
            self.vehicles.append(value)
