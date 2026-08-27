from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Enum, Text, Boolean
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
    client_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=True, index=True)

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
    extra_stops = Column(Integer, default=0, nullable=False)
    pickup_floor = Column(Integer, nullable=True)
    delivery_floor = Column(Integer, nullable=True)
    pickup_has_elevator = Column(Boolean, default=True, nullable=False)
    delivery_has_elevator = Column(Boolean, default=True, nullable=False)
    service_type = Column(String(32), nullable=True)

    estimated_duration_minutes = Column(Float, nullable=True)
    actual_distance_km = Column(Float, nullable=True)
    recommended_vehicle_type = Column(String(32), nullable=True)
    selected_vehicle_type = Column(String(32), nullable=True)
    pricing_version = Column(String(32), nullable=True)
    pricing_type = Column(String(32), nullable=False, default="automatic")
    requires_manual_quote = Column(Boolean, nullable=False, default=False)
    route_provider = Column(String(40), nullable=True)
    route_calculated_at = Column(DateTime(timezone=True), nullable=True)
    quote_expires_at = Column(DateTime(timezone=True), nullable=True)
    actual_vehicle_id = Column(
        Integer,
        ForeignKey("vehicles.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    estimated_price = Column(Float, nullable=True)
        # Después de estimated_price:
    is_urgent        = Column(Boolean, default=False)
    base_price       = Column(Float, nullable=True)
    client_pays      = Column(Float, nullable=True)   # estimated_price va aquí
    driver_receives  = Column(Float, nullable=True)
    platform_fee     = Column(Float, nullable=True)
    helpers_cost     = Column(Float, nullable=True)
    mode             = Column(String, default="scheduled")  # scheduled / urgent
    final_price = Column(Float, nullable=True)
    status = Column(Enum(FreightStatus), default=FreightStatus.pending, index=True)

    scheduled_at = Column(DateTime(timezone=True), nullable=True)
    accepted_at = Column(DateTime(timezone=True), nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    cancelled_at = Column(DateTime(timezone=True), nullable=True)
    cancel_reason = Column(String, nullable=True)
    requested_at = Column(DateTime(timezone=True), nullable=True)
    price_estimated_at = Column(DateTime(timezone=True), nullable=True)
    customer_confirmed_at = Column(DateTime(timezone=True), nullable=True)
    driver_assigned_at = Column(DateTime(timezone=True), nullable=True)
    driver_accepted_at = Column(DateTime(timezone=True), nullable=True)
    driver_arrived_pickup_at = Column(DateTime(timezone=True), nullable=True)
    trip_started_at = Column(DateTime(timezone=True), nullable=True)
    driver_arrived_destination_at = Column(DateTime(timezone=True), nullable=True)
    trip_completed_at = Column(DateTime(timezone=True), nullable=True)

    pickup_photo_ref = Column(String, nullable=True)
    pickup_photo_uploaded_at = Column(DateTime(timezone=True), nullable=True)
    delivery_photo_ref = Column(String, nullable=True)
    delivery_photo_uploaded_at = Column(DateTime(timezone=True), nullable=True)
    delivery_pin_hash = Column(String, nullable=True)
    delivery_pin_generated_at = Column(DateTime(timezone=True), nullable=True)
    delivery_pin_verified_at = Column(DateTime(timezone=True), nullable=True)
    delivery_pin_failed_attempts = Column(Integer, default=0, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    last_modified_by = Column(Integer, nullable=True)

    client = relationship("User", back_populates="freight_requests", foreign_keys=[client_id])
    driver = relationship("Driver", back_populates="freight_requests", foreign_keys=[driver_id])
    status_history = relationship("TripStatusHistory", back_populates="freight")
    payment = relationship("Payment", back_populates="freight", uselist=False)
    rating = relationship("Rating", back_populates="freight", uselist=False)
    driver_payout = relationship("DriverPayout", back_populates="freight", uselist=False)
    pricing_snapshots = relationship(
        "FreightPricingSnapshot",
        back_populates="freight",
        order_by="FreightPricingSnapshot.captured_at",
    )
    pricing_quotes = relationship("FreightPriceQuote", back_populates="freight")
    chat_messages = relationship(
        "FreightChatMessage",
        back_populates="freight",
        cascade="all, delete-orphan",
        order_by="FreightChatMessage.created_at",
    )

    @property
    def has_pickup_photo(self) -> bool:
        return bool(self.pickup_photo_ref)

    @property
    def has_delivery_photo(self) -> bool:
        return bool(self.delivery_photo_ref)

    @property
    def delivery_pin_ready(self) -> bool:
        return bool(self.delivery_pin_hash)

    @property
    def delivery_pin_verified(self) -> bool:
        return bool(self.delivery_pin_verified_at)

    @property
    def payment_id(self) -> int | None:
        return self.payment.id if self.payment else None

    @property
    def payment_status(self) -> str | None:
        if not self.payment:
            return None
        return (
            self.payment.status.value
            if hasattr(self.payment.status, "value")
            else str(self.payment.status)
        )

    @property
    def rating_score(self) -> float | None:
        return self.rating.score if self.rating else None

    @property
    def rating_comment(self) -> str | None:
        return self.rating.comment if self.rating else None

    @property
    def driver_summary(self) -> dict | None:
        if not self.driver:
            return None

        vehicle = self.driver.vehicle
        return {
            "id": self.driver.id,
            "full_name": self.driver.user.full_name if self.driver.user else "Conductor",
            "rating_average": self.driver.rating_average or 0,
            "rating_count": self.driver.rating_count or 0,
            "total_trips": self.driver.total_trips or 0,
            "is_verified": (
                self.driver.status.value
                if hasattr(self.driver.status, "value")
                else str(self.driver.status)
            )
            == "approved",
            "profile_image_url": None,
            "vehicle": {
                "type": vehicle.type.value if hasattr(vehicle.type, "value") else str(vehicle.type),
                "brand": vehicle.brand,
                "model": vehicle.model,
                "year": vehicle.year,
                "plate": vehicle.plate,
                "color": vehicle.color,
            }
            if vehicle
            else None,
        }


class TripStatusHistory(Base):
    __tablename__ = "trip_status_history"

    id = Column(Integer, primary_key=True, index=True)
    freight_id = Column(Integer, ForeignKey("freight_requests.id"), nullable=False, index=True)
    status = Column(Enum(FreightStatus), nullable=False)
    note = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    freight = relationship("FreightRequest", back_populates="status_history")
