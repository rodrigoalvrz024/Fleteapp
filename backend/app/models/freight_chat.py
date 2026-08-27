from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class FreightChatMessage(Base):
    """A coordination message between the two participants of one freight."""

    __tablename__ = "freight_chat_messages"

    id = Column(Integer, primary_key=True, index=True)
    freight_id = Column(
        Integer,
        ForeignKey("freight_requests.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sender_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    receiver_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    message_text = Column(Text, nullable=False)
    message_type = Column(String(20), nullable=False, default="text")
    attachment_ref = Column(String(512), nullable=True)
    attachment_content_type = Column(String(80), nullable=True)
    attachment_size_bytes = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    read_at = Column(DateTime(timezone=True), nullable=True)

    freight = relationship("FreightRequest", back_populates="chat_messages")
    sender = relationship("User", foreign_keys=[sender_user_id])
    receiver = relationship("User", foreign_keys=[receiver_user_id])
