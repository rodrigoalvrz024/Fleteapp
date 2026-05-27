import enum

from sqlalchemy import Column, DateTime, Enum, ForeignKey, Integer, String, Text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class DataPrivacyRequestType(str, enum.Enum):
    account_deletion = "account_deletion"
    data_export = "data_export"
    data_rectification = "data_rectification"


class DataPrivacyRequestStatus(str, enum.Enum):
    pending = "pending"
    in_review = "in_review"
    resolved = "resolved"
    rejected = "rejected"


class DataPrivacyRequest(Base):
    __tablename__ = "data_privacy_requests"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    request_type = Column(Enum(DataPrivacyRequestType), nullable=False, index=True)
    status = Column(
        Enum(DataPrivacyRequestStatus),
        default=DataPrivacyRequestStatus.pending,
        nullable=False,
        index=True,
    )
    message = Column(Text, nullable=True)
    admin_response = Column(Text, nullable=True)
    resolved_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    resolved_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    user = relationship("User", foreign_keys=[user_id])
    resolver = relationship("User", foreign_keys=[resolved_by])
