"""Add per-account session generation without invalidating untouched accounts."""

from alembic import op
import sqlalchemy as sa

revision = "a7d2e9c1f630"
down_revision = "f6b8c0d2e411"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("SET LOCAL lock_timeout = '5s'")
    columns = {column["name"]: column for column in sa.inspect(op.get_bind()).get_columns("users")}
    existing = columns.get("session_version")
    if existing is not None:
        # Older startup-created schemas may already include the model column.
        if not isinstance(existing["type"], sa.Integer) or existing["nullable"]:
            raise RuntimeError("Unexpected session_version schema; manual review required")
        return
    op.add_column("users", sa.Column("session_version", sa.Integer(), nullable=False, server_default="0"))


def downgrade():
    raise RuntimeError("Session revocation cannot be discarded safely; use a forward migration")
