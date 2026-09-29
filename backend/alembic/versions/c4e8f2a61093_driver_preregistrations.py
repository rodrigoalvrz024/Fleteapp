"""Store launch preregistrations independently from operational user accounts."""
from alembic import op
import sqlalchemy as sa

revision = "c4e8f2a61093"
down_revision = "e1f0a2b3c4d5"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "driver_preregistrations",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("full_name", sa.String(100), nullable=False),
        sa.Column("email", sa.String(254), nullable=False, unique=True),
        sa.Column("phone", sa.String(12), nullable=False),
        sa.Column("commune", sa.String(80), nullable=False),
        sa.Column("vehicle_type", sa.String(30), nullable=False),
        sa.Column("availability", sa.String(30)),
        sa.Column("contact_consent", sa.Boolean(), nullable=False),
        sa.Column("marketing_consent", sa.Boolean(), nullable=False),
        sa.Column("consent_version", sa.String(30), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("sheets_synced_at", sa.DateTime(timezone=True)),
    )
    op.create_index("ix_driver_preregistrations_sheets_synced_at", "driver_preregistrations", ["sheets_synced_at"])
    if op.get_bind().dialect.name == "postgresql":
        op.execute("ALTER TABLE driver_preregistrations ENABLE ROW LEVEL SECURITY")
        op.execute("REVOKE ALL ON driver_preregistrations FROM PUBLIC")
        for role in ("anon", "authenticated"):
            if op.get_bind().execute(sa.text("SELECT 1 FROM pg_roles WHERE rolname = :role"), {"role": role}).scalar():
                op.execute(f"REVOKE ALL ON driver_preregistrations FROM {role}")


def downgrade():
    raise RuntimeError("Preserve preregistrations; use a reviewed forward migration")
