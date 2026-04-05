from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.database import Base

class Rating(Base):
    __tablename__ = "ratings"

    id = Column(Integer, primary_key=True, index=True)
    freight_id = Column(Integer, ForeignKey("freight_requests.id"), unique=True, nullable=False)
    rater_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    rated_driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=False)
    score = Column(Float, nullable=False)
    comment = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    freight = relationship("FreightRequest", back_populates="rating")
    rater = relationship("User", back_populates="ratings_given", foreign_keys=[rater_id])