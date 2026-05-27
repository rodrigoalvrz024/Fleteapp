from sqlalchemy import Column, DateTime, ForeignKey, Integer, JSON, String, Text
from sqlalchemy.sql import func

from app.database import Base


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id = Column(Integer, primary_key=True, index=True)
    occurred_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    actor_user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    actor_role = Column(String(32), nullable=True)
    entity_type = Column(String(80), nullable=False, index=True)
    entity_id = Column(String(64), nullable=False, index=True)
    event_type = Column(String(80), nullable=False, index=True)
    before_data = Column(JSON, nullable=True)
    after_data = Column(JSON, nullable=True)
    reason = Column(Text, nullable=True)
    ip_address = Column(String(64), nullable=True)
    user_agent = Column(String(255), nullable=True)
    request_id = Column(String(128), nullable=True, index=True)
    event_metadata = Column("metadata", JSON, nullable=True)
