"""Administrative MFA on the deployed support-FAQ baseline.

This revision deliberately does not depend on unreleased payment/vehicle work.
"""
from alembic import op
import sqlalchemy as sa

revision = "f30c6a8b210d"
down_revision = "b2e4f6a81047"
branch_labels = None
depends_on = None


def upgrade():
    connection = op.get_bind()
    if connection.dialect.name != "postgresql":
        raise RuntimeError("Administrative MFA migration requires PostgreSQL")
    op.execute("SET LOCAL lock_timeout = '5s'")
    op.add_column("users", sa.Column("session_version", sa.Integer(), nullable=False, server_default="0"))
    op.create_table(
        "admin_second_factors",
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("encrypted_secret", sa.String(512), nullable=False),
        sa.Column("last_counter", sa.Integer(), nullable=False),
        sa.Column("failures", sa.Integer(), nullable=False),
        sa.Column("locked_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("activated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.execute("ALTER TABLE public.admin_second_factors ENABLE ROW LEVEL SECURITY")
    op.execute("REVOKE ALL ON TABLE public.admin_second_factors FROM PUBLIC")
    for role in ("anon", "authenticated"):
        exists = connection.execute(sa.text("SELECT 1 FROM pg_roles WHERE rolname = :role"), {"role": role}).scalar()
        if exists:
            op.execute(f"REVOKE ALL ON TABLE public.admin_second_factors FROM {role}")


def downgrade():
    raise RuntimeError("Do not remove MFA factors automatically; use a reviewed recovery plan")
