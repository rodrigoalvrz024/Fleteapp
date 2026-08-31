"""add active driver live location

Revision ID: da6e7f8a9b10
Revises: c4e7d9a1f302
Create Date: 2026-08-31
"""

from alembic import op
import sqlalchemy as sa


revision = "da6e7f8a9b10"
down_revision = "c4e7d9a1f302"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "freight_requests",
        sa.Column("driver_location_lat", sa.Float(), nullable=True),
    )
    op.add_column(
        "freight_requests",
        sa.Column("driver_location_lng", sa.Float(), nullable=True),
    )
    op.add_column(
        "freight_requests",
        sa.Column("driver_location_accuracy_m", sa.Float(), nullable=True),
    )
    op.add_column(
        "freight_requests",
        sa.Column("driver_location_heading", sa.Float(), nullable=True),
    )
    op.add_column(
        "freight_requests",
        sa.Column("driver_location_updated_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    for column in (
        "driver_location_updated_at",
        "driver_location_heading",
        "driver_location_accuracy_m",
        "driver_location_lng",
        "driver_location_lat",
    ):
        op.drop_column("freight_requests", column)
