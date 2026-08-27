from sqlalchemy import Column, DateTime, ForeignKey, Integer, UniqueConstraint
from sqlalchemy.sql import func

from app.database import Base


class FreightDriverDecline(Base):
    """A driver decision not to receive the same pending freight again."""

    __tablename__ = "freight_driver_declines"
    __table_args__ = (
        UniqueConstraint("freight_id", "driver_id", name="uq_freight_driver_declines_freight_driver"),
    )

    id = Column(Integer, primary_key=True, index=True)
    freight_id = Column(
        Integer,
        ForeignKey("freight_requests.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    driver_id = Column(
        Integer,
        ForeignKey("drivers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
