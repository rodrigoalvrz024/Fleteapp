"""add immutable freight pricing history

Revision ID: 8b4e7c2a9f10
Revises: 1ccc69b7d757
Create Date: 2026-08-12
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "8b4e7c2a9f10"
down_revision: Union[str, None] = "1ccc69b7d757"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "freight_requests",
        sa.Column("service_type", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "freight_requests",
        sa.Column("estimated_duration_minutes", sa.Float(), nullable=True),
    )
    op.add_column(
        "freight_requests",
        sa.Column("actual_distance_km", sa.Float(), nullable=True),
    )
    op.add_column(
        "freight_requests",
        sa.Column("recommended_vehicle_type", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "freight_requests",
        sa.Column("selected_vehicle_type", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "freight_requests",
        sa.Column("actual_vehicle_id", sa.Integer(), nullable=True),
    )
    op.create_foreign_key(
        "fk_freight_requests_actual_vehicle_id_vehicles",
        "freight_requests",
        "vehicles",
        ["actual_vehicle_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_freight_requests_actual_vehicle_id",
        "freight_requests",
        ["actual_vehicle_id"],
        unique=False,
    )
    for name in (
        "requested_at",
        "price_estimated_at",
        "customer_confirmed_at",
        "driver_assigned_at",
        "driver_accepted_at",
        "driver_arrived_pickup_at",
        "trip_started_at",
        "driver_arrived_destination_at",
        "trip_completed_at",
    ):
        op.add_column(
            "freight_requests",
            sa.Column(name, sa.DateTime(timezone=True), nullable=True),
        )

    op.create_table(
        "freight_pricing_snapshots",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("freight_id", sa.Integer(), nullable=False),
        sa.Column("snapshot_type", sa.String(length=40), nullable=False),
        sa.Column("pricing_version", sa.String(length=32), nullable=False),
        sa.Column("pricing_type", sa.String(length=32), nullable=False),
        sa.Column(
            "captured_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("estimated_customer_price", sa.Float(), nullable=True),
        sa.Column("accepted_customer_price", sa.Float(), nullable=True),
        sa.Column("final_customer_price", sa.Float(), nullable=True),
        sa.Column("estimated_driver_earnings", sa.Float(), nullable=True),
        sa.Column("final_driver_earnings", sa.Float(), nullable=True),
        sa.Column("estimated_platform_fee", sa.Float(), nullable=True),
        sa.Column("final_platform_fee", sa.Float(), nullable=True),
        sa.Column("gross_price", sa.Float(), nullable=True),
        sa.Column("discount_amount", sa.Float(), nullable=True),
        sa.Column("promotion_id", sa.String(length=80), nullable=True),
        sa.Column("price_adjustment_amount", sa.Float(), nullable=True),
        sa.Column("price_adjustment_reason", sa.String(length=80), nullable=True),
        sa.Column("base_fare", sa.Float(), nullable=True),
        sa.Column("distance_charge", sa.Float(), nullable=True),
        sa.Column("weight_charge", sa.Float(), nullable=True),
        sa.Column("time_charge", sa.Float(), nullable=True),
        sa.Column("extras_charge", sa.Float(), nullable=True),
        sa.Column("estimated_tolls", sa.Float(), nullable=True),
        sa.Column("urgency_charge", sa.Float(), nullable=True),
        sa.Column("helper_charge", sa.Float(), nullable=True),
        sa.Column("tax_amount", sa.Float(), nullable=True),
        sa.Column("calculation_metadata", sa.JSON(), nullable=True),
        sa.Column("estimated_distance_km", sa.Float(), nullable=True),
        sa.Column("actual_distance_km", sa.Float(), nullable=True),
        sa.Column("estimated_duration_minutes", sa.Float(), nullable=True),
        sa.Column("actual_duration_minutes", sa.Float(), nullable=True),
        sa.Column("recommended_vehicle_type", sa.String(length=32), nullable=True),
        sa.Column("selected_vehicle_type", sa.String(length=32), nullable=True),
        sa.Column("actual_vehicle_id", sa.Integer(), nullable=True),
        sa.Column("actual_vehicle_type", sa.String(length=32), nullable=True),
        sa.Column("actual_vehicle_brand", sa.String(length=80), nullable=True),
        sa.Column("actual_vehicle_model", sa.String(length=80), nullable=True),
        sa.Column("actual_vehicle_year", sa.Integer(), nullable=True),
        sa.Column("actual_vehicle_max_weight_kg", sa.Float(), nullable=True),
        sa.Column("actual_vehicle_max_volume_m3", sa.Float(), nullable=True),
        sa.Column("service_type", sa.String(length=32), nullable=True),
        sa.Column("estimated_weight_kg", sa.Float(), nullable=True),
        sa.Column("estimated_volume_m3", sa.Float(), nullable=True),
        sa.Column("helpers_count", sa.Integer(), nullable=True),
        sa.Column("extra_stops_count", sa.Integer(), nullable=True),
        sa.Column("urgent", sa.Boolean(), nullable=True),
        sa.Column("pickup_commune", sa.String(length=100), nullable=True),
        sa.Column("dropoff_commune", sa.String(length=100), nullable=True),
        sa.Column("requested_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("price_estimated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("customer_confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("driver_assigned_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("driver_accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("driver_arrived_pickup_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("trip_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("driver_arrived_destination_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("trip_completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["actual_vehicle_id"], ["vehicles.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["freight_id"], ["freight_requests.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_freight_pricing_snapshots_id",
        "freight_pricing_snapshots",
        ["id"],
        unique=False,
    )
    op.create_index(
        "ix_freight_pricing_snapshots_freight_id",
        "freight_pricing_snapshots",
        ["freight_id"],
        unique=False,
    )
    op.create_index(
        "ix_freight_pricing_snapshots_snapshot_type",
        "freight_pricing_snapshots",
        ["snapshot_type"],
        unique=False,
    )
    op.create_index(
        "ix_freight_pricing_snapshots_freight_captured",
        "freight_pricing_snapshots",
        ["freight_id", "captured_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_freight_pricing_snapshots_freight_captured", table_name="freight_pricing_snapshots")
    op.drop_index("ix_freight_pricing_snapshots_snapshot_type", table_name="freight_pricing_snapshots")
    op.drop_index("ix_freight_pricing_snapshots_freight_id", table_name="freight_pricing_snapshots")
    op.drop_index("ix_freight_pricing_snapshots_id", table_name="freight_pricing_snapshots")
    op.drop_table("freight_pricing_snapshots")
    for name in (
        "trip_completed_at",
        "driver_arrived_destination_at",
        "trip_started_at",
        "driver_arrived_pickup_at",
        "driver_accepted_at",
        "driver_assigned_at",
        "customer_confirmed_at",
        "price_estimated_at",
        "requested_at",
    ):
        op.drop_column("freight_requests", name)
    op.drop_index("ix_freight_requests_actual_vehicle_id", table_name="freight_requests")
    op.drop_constraint(
        "fk_freight_requests_actual_vehicle_id_vehicles",
        "freight_requests",
        type_="foreignkey",
    )
    for name in (
        "actual_vehicle_id",
        "selected_vehicle_type",
        "recommended_vehicle_type",
        "actual_distance_km",
        "estimated_duration_minutes",
        "service_type",
    ):
        op.drop_column("freight_requests", name)
