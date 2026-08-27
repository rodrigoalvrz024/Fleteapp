"""add private chat image attachments

Revision ID: 7c91d5a8e240
Revises: 4f8b7c2d1e90
Create Date: 2026-08-26
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "7c91d5a8e240"
down_revision: Union[str, None] = "4f8b7c2d1e90"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "freight_chat_messages",
        sa.Column("attachment_ref", sa.String(length=512), nullable=True),
    )
    op.add_column(
        "freight_chat_messages",
        sa.Column("attachment_content_type", sa.String(length=80), nullable=True),
    )
    op.add_column(
        "freight_chat_messages",
        sa.Column("attachment_size_bytes", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("freight_chat_messages", "attachment_size_bytes")
    op.drop_column("freight_chat_messages", "attachment_content_type")
    op.drop_column("freight_chat_messages", "attachment_ref")
