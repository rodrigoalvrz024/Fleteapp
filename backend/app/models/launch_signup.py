from datetime import datetime, timezone
from sqlalchemy import Boolean, Column, DateTime, Integer, String
from app.database import Base


class LaunchSignup(Base):
    __tablename__ = "launch_signups"
    id = Column(Integer, primary_key=True, autoincrement=True)
    full_name = Column(String(100), nullable=False)
    email = Column(String(254), nullable=False, unique=True)
    phone = Column(String(12), nullable=False)
    platform = Column(String(10), nullable=False)
    email_consent = Column(Boolean, nullable=False)
    whatsapp_consent = Column(Boolean, nullable=False)
    consent_version = Column(String(30), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    sheets_synced_at = Column(DateTime(timezone=True), nullable=True, index=True)
