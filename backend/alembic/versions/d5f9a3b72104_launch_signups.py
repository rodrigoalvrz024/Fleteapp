"""Store launch preregistrations independently from operational user accounts."""
from alembic import op
import sqlalchemy as sa

revision = "d5f9a3b72104"
down_revision = "c4e8f2a61093"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "launch_signups",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("full_name", sa.String(100), nullable=False),
        sa.Column("email", sa.String(254), nullable=False, unique=True),
        sa.Column("phone", sa.String(12), nullable=False),
        sa.Column("platform", sa.String(10), nullable=False),
        sa.Column("email_consent", sa.Boolean(), nullable=False),
        sa.Column("whatsapp_consent", sa.Boolean(), nullable=False),
        sa.Column("consent_version", sa.String(30), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("sheets_synced_at", sa.DateTime(timezone=True)),
    )
    op.create_index("ix_launch_signups_sheets_synced_at", "launch_signups", ["sheets_synced_at"])
    if op.get_bind().dialect.name == "postgresql":
        op.execute("ALTER TABLE launch_signups ENABLE ROW LEVEL SECURITY")
        op.execute("REVOKE ALL ON launch_signups FROM PUBLIC")
        for role in ("anon", "authenticated"):
            if op.get_bind().execute(sa.text("SELECT 1 FROM pg_roles WHERE rolname = :role"), {"role": role}).scalar():
                op.execute(f"REVOKE ALL ON launch_signups FROM {role}")


def downgrade():
    raise RuntimeError("Preserve preregistrations; use a reviewed forward migration")
