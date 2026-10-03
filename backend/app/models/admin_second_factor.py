from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from app.database import Base


class AdminSecondFactor(Base):
    __tablename__ = "admin_second_factors"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    encrypted_secret = Column(String(512), nullable=False)
    last_counter = Column(Integer, nullable=False, default=-1)
    failures = Column(Integer, nullable=False, default=0)
    locked_until = Column(DateTime(timezone=True), nullable=True)
    activated_at = Column(DateTime(timezone=True), nullable=False)
