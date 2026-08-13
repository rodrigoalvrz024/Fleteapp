from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer, JSON, String
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class FreightPriceQuote(Base):
    """Short-lived, server-generated estimate accepted by a client exactly once."""

    __tablename__ = "freight_price_quotes"

    id = Column(String(64), primary_key=True)
    client_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    freight_id = Column(Integer, ForeignKey("freight_requests.id", ondelete="SET NULL"), nullable=True, index=True)
    request_fingerprint = Column(String(64), nullable=False, index=True)
    route_distance_km = Column(Float, nullable=False)
    route_duration_minutes = Column(Float, nullable=False)
    route_provider = Column(String(40), nullable=False)
    route_calculated_at = Column(DateTime(timezone=True), nullable=False)
    recommended_vehicle_type = Column(String(32), nullable=True)
    selected_vehicle_type = Column(String(32), nullable=True)
    pricing_version = Column(String(32), nullable=False)
    pricing_type = Column(String(32), nullable=False, default="automatic")
    pricing_components = Column(JSON, nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False, index=True)
    used_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    freight = relationship("FreightRequest", back_populates="pricing_quotes")
