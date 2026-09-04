"""add account roles for shared customer and driver identities

Revision ID: e1f0a2b3c4d5
Revises: da6e7f8a9b10
Create Date: 2026-09-03
"""

from alembic import op
import sqlalchemy as sa


revision = "e1f0a2b3c4d5"
down_revision = "da6e7f8a9b10"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("account_roles", sa.JSON(), nullable=True))
    op.execute(
        """
        UPDATE users
        SET account_roles = CASE
            WHEN role::text = 'driver' THEN '["client", "driver"]'::jsonb
            WHEN role::text = 'admin' THEN '["admin"]'::jsonb
            ELSE '["client"]'::jsonb
        END
        """
    )
    op.alter_column("users", "account_roles", nullable=False)


def downgrade() -> None:
    op.drop_column("users", "account_roles")
