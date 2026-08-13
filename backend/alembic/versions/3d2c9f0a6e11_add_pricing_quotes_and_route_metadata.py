"""add pricing quotes and route metadata

Revision ID: 3d2c9f0a6e11
Revises: 8b4e7c2a9f10
Create Date: 2026-08-13
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "3d2c9f0a6e11"
down_revision: Union[str, None] = "8b4e7c2a9f10"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "freight_requests",
        sa.Column("extra_stops", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column("freight_requests", sa.Column("pickup_floor", sa.Integer(), nullable=True))
    op.add_column("freight_requests", sa.Column("delivery_floor", sa.Integer(), nullable=True))
    op.add_column(
        "freight_requests",
        sa.Column("pickup_has_elevator", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.add_column(
        "freight_requests",
        sa.Column("delivery_has_elevator", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.add_column("freight_requests", sa.Column("pricing_version", sa.String(length=32), nullable=True))
    op.add_column(
        "freight_requests",
        sa.Column("pricing_type", sa.String(length=32), nullable=False, server_default="automatic"),
    )
    op.add_column(
        "freight_requests",
        sa.Column("requires_manual_quote", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column("freight_requests", sa.Column("route_provider", sa.String(length=40), nullable=True))
    op.add_column(
        "freight_requests", sa.Column("route_calculated_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "freight_requests", sa.Column("quote_expires_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.create_table(
        "freight_price_quotes",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("client_id", sa.Integer(), nullable=False),
        sa.Column("freight_id", sa.Integer(), nullable=True),
        sa.Column("request_fingerprint", sa.String(length=64), nullable=False),
        sa.Column("route_distance_km", sa.Float(), nullable=False),
        sa.Column("route_duration_minutes", sa.Float(), nullable=False),
        sa.Column("route_provider", sa.String(length=40), nullable=False),
        sa.Column("route_calculated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("recommended_vehicle_type", sa.String(length=32), nullable=True),
        sa.Column("selected_vehicle_type", sa.String(length=32), nullable=True),
        sa.Column("pricing_version", sa.String(length=32), nullable=False),
        sa.Column("pricing_type", sa.String(length=32), nullable=False, server_default="automatic"),
        sa.Column("pricing_components", sa.JSON(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["client_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["freight_id"], ["freight_requests.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    for name, columns in (
        ("ix_freight_price_quotes_client_id", ["client_id"]),
        ("ix_freight_price_quotes_freight_id", ["freight_id"]),
        ("ix_freight_price_quotes_request_fingerprint", ["request_fingerprint"]),
        ("ix_freight_price_quotes_expires_at", ["expires_at"]),
    ):
        op.create_index(name, "freight_price_quotes", columns, unique=False)


def downgrade() -> None:
    for name in (
        "ix_freight_price_quotes_expires_at",
        "ix_freight_price_quotes_request_fingerprint",
        "ix_freight_price_quotes_freight_id",
        "ix_freight_price_quotes_client_id",
    ):
        op.drop_index(name, table_name="freight_price_quotes")
    op.drop_table("freight_price_quotes")
    for name in (
        "quote_expires_at",
        "route_calculated_at",
        "route_provider",
        "requires_manual_quote",
        "pricing_type",
        "pricing_version",
        "delivery_has_elevator",
        "pickup_has_elevator",
        "delivery_floor",
        "pickup_floor",
        "extra_stops",
    ):
        op.drop_column("freight_requests", name)
