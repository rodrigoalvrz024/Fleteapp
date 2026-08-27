"""add private freight chat messages

Revision ID: 4f8b7c2d1e90
Revises: 3d2c9f0a6e11
Create Date: 2026-08-13
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "4f8b7c2d1e90"
down_revision: Union[str, None] = "3d2c9f0a6e11"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "freight_chat_messages",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("freight_id", sa.Integer(), nullable=False),
        sa.Column("sender_user_id", sa.Integer(), nullable=False),
        sa.Column("receiver_user_id", sa.Integer(), nullable=False),
        sa.Column("message_text", sa.Text(), nullable=False),
        sa.Column("message_type", sa.String(length=20), nullable=False, server_default="text"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["freight_id"], ["freight_requests.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["receiver_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["sender_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_freight_chat_messages_freight_id", "freight_chat_messages", ["freight_id"], unique=False)
    op.create_index("ix_freight_chat_messages_sender_user_id", "freight_chat_messages", ["sender_user_id"], unique=False)
    op.create_index("ix_freight_chat_messages_receiver_user_id", "freight_chat_messages", ["receiver_user_id"], unique=False)
    op.create_index("ix_freight_chat_messages_freight_created", "freight_chat_messages", ["freight_id", "created_at"], unique=False)
    op.create_table(
        "freight_driver_declines",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("freight_id", sa.Integer(), nullable=False),
        sa.Column("driver_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.ForeignKeyConstraint(["freight_id"], ["freight_requests.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["driver_id"], ["drivers.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("freight_id", "driver_id", name="uq_freight_driver_declines_freight_driver"),
    )
    op.create_index("ix_freight_driver_declines_freight_id", "freight_driver_declines", ["freight_id"], unique=False)
    op.create_index("ix_freight_driver_declines_driver_id", "freight_driver_declines", ["driver_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_freight_driver_declines_driver_id", table_name="freight_driver_declines")
    op.drop_index("ix_freight_driver_declines_freight_id", table_name="freight_driver_declines")
    op.drop_table("freight_driver_declines")
    op.drop_index("ix_freight_chat_messages_freight_created", table_name="freight_chat_messages")
    op.drop_index("ix_freight_chat_messages_receiver_user_id", table_name="freight_chat_messages")
    op.drop_index("ix_freight_chat_messages_sender_user_id", table_name="freight_chat_messages")
    op.drop_index("ix_freight_chat_messages_freight_id", table_name="freight_chat_messages")
    op.drop_table("freight_chat_messages")
