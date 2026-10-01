from datetime import datetime, timezone

from sqlalchemy import Boolean, CheckConstraint, Column, DateTime, Index, Integer, String, Text

from app.database import Base


class SupportFAQ(Base):
    __tablename__ = "support_faqs"
    id = Column(Integer, primary_key=True)
    slug = Column(String(80), nullable=False, unique=True)
    category = Column(String(24), nullable=False)
    question = Column(String(200), nullable=False)
    answer = Column(Text, nullable=False)
    audience = Column(String(10), nullable=False, default="all")
    published = Column(Boolean, nullable=False, default=False)
    sort_order = Column(Integer, nullable=False, default=0)
    version = Column(Integer, nullable=False, default=1)
    updated_at = Column(DateTime(timezone=True), nullable=False,
                        default=lambda: datetime.now(timezone.utc))
    __table_args__ = (
        CheckConstraint("audience IN ('all','client','driver')", name="ck_support_faq_audience"),
        CheckConstraint("category IN ('requests','payments','account','safety')", name="ck_support_faq_category"),
        CheckConstraint("version >= 1", name="ck_support_faq_version"),
        Index("ix_support_faq_visible", "published", "audience", "sort_order", "id"),
    )
