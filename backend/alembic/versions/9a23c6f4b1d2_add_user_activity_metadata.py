"""add user activity metadata

Revision ID: 9a23c6f4b1d2
Revises: 7c91d5a8e240
Create Date: 2026-08-26 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa


revision = "9a23c6f4b1d2"
down_revision = "7c91d5a8e240"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("last_seen_screen", sa.String(length=120), nullable=True))
    op.create_index("ix_users_last_login_at", "users", ["last_login_at"])
    op.create_index("ix_users_last_seen_at", "users", ["last_seen_at"])


def downgrade() -> None:
    op.drop_index("ix_users_last_seen_at", table_name="users")
    op.drop_index("ix_users_last_login_at", table_name="users")
    op.drop_column("users", "last_seen_screen")
    op.drop_column("users", "last_seen_at")
    op.drop_column("users", "last_login_at")
