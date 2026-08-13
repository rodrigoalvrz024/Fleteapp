from sqlalchemy import (
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    Boolean,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class FreightPricingSnapshot(Base):
    """Append-only record of the pricing and operational state of a freight.

    A freight remains the current operational view. This table preserves the
    inputs and financial result known at every relevant point in its lifecycle.
    It is intentionally not exposed through the client or driver APIs.
    """

    __tablename__ = "freight_pricing_snapshots"
    __table_args__ = (
        Index(
            "ix_freight_pricing_snapshots_freight_captured",
            "freight_id",
            "captured_at",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    freight_id = Column(
        Integer,
        ForeignKey("freight_requests.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    snapshot_type = Column(String(40), nullable=False, index=True)
    pricing_version = Column(String(32), nullable=False)
    pricing_type = Column(String(32), nullable=False)
    captured_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    estimated_customer_price = Column(Float, nullable=True)
    accepted_customer_price = Column(Float, nullable=True)
    final_customer_price = Column(Float, nullable=True)
    estimated_driver_earnings = Column(Float, nullable=True)
    final_driver_earnings = Column(Float, nullable=True)
    estimated_platform_fee = Column(Float, nullable=True)
    final_platform_fee = Column(Float, nullable=True)
    gross_price = Column(Float, nullable=True)
    discount_amount = Column(Float, nullable=True)
    promotion_id = Column(String(80), nullable=True)
    price_adjustment_amount = Column(Float, nullable=True)
    price_adjustment_reason = Column(String(80), nullable=True)

    base_fare = Column(Float, nullable=True)
    distance_charge = Column(Float, nullable=True)
    weight_charge = Column(Float, nullable=True)
    time_charge = Column(Float, nullable=True)
    extras_charge = Column(Float, nullable=True)
    estimated_tolls = Column(Float, nullable=True)
    urgency_charge = Column(Float, nullable=True)
    helper_charge = Column(Float, nullable=True)
    tax_amount = Column(Float, nullable=True)
    calculation_metadata = Column(JSON, nullable=True)

    estimated_distance_km = Column(Float, nullable=True)
    actual_distance_km = Column(Float, nullable=True)
    estimated_duration_minutes = Column(Float, nullable=True)
    actual_duration_minutes = Column(Float, nullable=True)

    recommended_vehicle_type = Column(String(32), nullable=True)
    selected_vehicle_type = Column(String(32), nullable=True)
    actual_vehicle_id = Column(
        Integer,
        ForeignKey("vehicles.id", ondelete="SET NULL"),
        nullable=True,
    )
    actual_vehicle_type = Column(String(32), nullable=True)
    actual_vehicle_brand = Column(String(80), nullable=True)
    actual_vehicle_model = Column(String(80), nullable=True)
    actual_vehicle_year = Column(Integer, nullable=True)
    actual_vehicle_max_weight_kg = Column(Float, nullable=True)
    actual_vehicle_max_volume_m3 = Column(Float, nullable=True)

    service_type = Column(String(32), nullable=True)
    estimated_weight_kg = Column(Float, nullable=True)
    estimated_volume_m3 = Column(Float, nullable=True)
    helpers_count = Column(Integer, nullable=True)
    extra_stops_count = Column(Integer, nullable=True)
    urgent = Column(Boolean, nullable=True)
    pickup_commune = Column(String(100), nullable=True)
    dropoff_commune = Column(String(100), nullable=True)

    requested_at = Column(DateTime(timezone=True), nullable=True)
    price_estimated_at = Column(DateTime(timezone=True), nullable=True)
    customer_confirmed_at = Column(DateTime(timezone=True), nullable=True)
    driver_assigned_at = Column(DateTime(timezone=True), nullable=True)
    driver_accepted_at = Column(DateTime(timezone=True), nullable=True)
    driver_arrived_pickup_at = Column(DateTime(timezone=True), nullable=True)
    trip_started_at = Column(DateTime(timezone=True), nullable=True)
    driver_arrived_destination_at = Column(DateTime(timezone=True), nullable=True)
    trip_completed_at = Column(DateTime(timezone=True), nullable=True)
    cancelled_at = Column(DateTime(timezone=True), nullable=True)

    freight = relationship("FreightRequest", back_populates="pricing_snapshots")
