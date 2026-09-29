from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, Integer, String

from app.database import Base


class DriverPreregistration(Base):
    __tablename__ = "driver_preregistrations"

    id = Column(Integer, primary_key=True, autoincrement=True)
    full_name = Column(String(100), nullable=False)
    email = Column(String(254), nullable=False, unique=True)
    phone = Column(String(12), nullable=False)
    commune = Column(String(80), nullable=False)
    vehicle_type = Column(String(30), nullable=False)
    availability = Column(String(30), nullable=True)
    contact_consent = Column(Boolean, nullable=False)
    marketing_consent = Column(Boolean, nullable=False, default=False)
    consent_version = Column(String(30), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    sheets_synced_at = Column(DateTime(timezone=True), nullable=True, index=True)
