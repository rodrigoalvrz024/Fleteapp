"""add vehicle matching, cargo photos and bilateral feedback

Revision ID: c4e7d9a1f302
Revises: 9a23c6f4b1d2
Create Date: 2026-08-30
"""

from alembic import op
import sqlalchemy as sa


revision = "c4e7d9a1f302"
down_revision = "9a23c6f4b1d2"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Existing verified vehicles remain usable. Every newly registered vehicle
    # receives the normal pending status from the database default below.
    op.execute("ALTER TABLE vehicles DROP CONSTRAINT IF EXISTS vehicles_driver_id_key")
    op.add_column("vehicles", sa.Column("catalog_id", sa.String(length=80), nullable=True))
    op.add_column(
        "vehicles",
        sa.Column("approval_status", sa.String(length=16), nullable=False, server_default="approved"),
    )
    op.add_column("vehicles", sa.Column("approval_reason", sa.String(length=500), nullable=True))
    op.add_column("vehicles", sa.Column("reviewed_by", sa.Integer(), nullable=True))
    op.add_column("vehicles", sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column(
        "vehicles",
        sa.Column("supported_service_types", sa.JSON(), nullable=False, server_default=sa.text("'[]'::json")),
    )
    op.create_foreign_key(
        "fk_vehicles_reviewed_by_users",
        "vehicles",
        "users",
        ["reviewed_by"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_vehicles_driver_id", "vehicles", ["driver_id"])
    op.create_index("ix_vehicles_catalog_id", "vehicles", ["catalog_id"])
    op.alter_column("vehicles", "approval_status", server_default="pending")
    op.alter_column("vehicles", "supported_service_types", server_default=None)

    op.create_table(
        "freight_cargo_photos",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("freight_id", sa.Integer(), nullable=False),
        sa.Column("client_id", sa.Integer(), nullable=False),
        sa.Column("object_ref", sa.String(length=512), nullable=False),
        sa.Column("content_type", sa.String(length=80), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["client_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["freight_id"], ["freight_requests.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("object_ref"),
    )
    op.create_index("ix_freight_cargo_photos_id", "freight_cargo_photos", ["id"])
    op.create_index("ix_freight_cargo_photos_freight_id", "freight_cargo_photos", ["freight_id"])

    op.create_table(
        "trip_feedback",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("freight_id", sa.Integer(), nullable=False),
        sa.Column("rater_id", sa.Integer(), nullable=False),
        sa.Column("recipient_role", sa.String(length=16), nullable=False),
        sa.Column("overall_score", sa.Float(), nullable=False),
        sa.Column("answers", sa.JSON(), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["freight_id"], ["freight_requests.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["rater_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("freight_id", "rater_id", name="uq_trip_feedback_freight_rater"),
    )
    op.create_index("ix_trip_feedback_id", "trip_feedback", ["id"])
    op.create_index("ix_trip_feedback_freight_id", "trip_feedback", ["freight_id"])


def downgrade() -> None:
    op.drop_index("ix_trip_feedback_freight_id", table_name="trip_feedback")
    op.drop_index("ix_trip_feedback_id", table_name="trip_feedback")
    op.drop_table("trip_feedback")
    op.drop_index("ix_freight_cargo_photos_freight_id", table_name="freight_cargo_photos")
    op.drop_index("ix_freight_cargo_photos_id", table_name="freight_cargo_photos")
    op.drop_table("freight_cargo_photos")
    op.drop_index("ix_vehicles_catalog_id", table_name="vehicles")
    op.drop_index("ix_vehicles_driver_id", table_name="vehicles")
    op.drop_constraint("fk_vehicles_reviewed_by_users", "vehicles", type_="foreignkey")
    op.drop_column("vehicles", "supported_service_types")
    op.drop_column("vehicles", "reviewed_at")
    op.drop_column("vehicles", "reviewed_by")
    op.drop_column("vehicles", "approval_reason")
    op.drop_column("vehicles", "approval_status")
    op.drop_column("vehicles", "catalog_id")
