from sqlalchemy import Column, DateTime, ForeignKey, Integer, JSON, String
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class DriverReviewAudit(Base):
    __tablename__ = "driver_review_audits"

    id = Column(Integer, primary_key=True, index=True)
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=False, index=True)
    admin_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    action = Column(String(32), nullable=False)
    status_before = Column(String(32), nullable=False)
    status_after = Column(String(32), nullable=False)
    reason = Column(String, nullable=True)
    documents_snapshot = Column(JSON, nullable=False)
    vehicle_snapshot = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    driver = relationship("Driver", back_populates="review_audits")
    admin = relationship("User")
