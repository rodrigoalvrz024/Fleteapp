"""Complete the schema formerly provisioned by startup code, without data changes.

Revision ID: f6b8c0d2e411
Revises: f2a4b6c8d010
Create Date: 2026-09-11
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "f6b8c0d2e411"
down_revision = "f2a4b6c8d010"
branch_labels = None
depends_on = None


def _tables():
    # Frozen definitions: later model edits must not change this migration.
    return {
        "audit_events": (
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("occurred_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.Column("actor_user_id", sa.Integer(), sa.ForeignKey("users.id")),
            sa.Column("actor_role", sa.String(32)),
            sa.Column("entity_type", sa.String(80), nullable=False),
            sa.Column("entity_id", sa.String(64), nullable=False),
            sa.Column("event_type", sa.String(80), nullable=False),
            sa.Column("before_data", sa.JSON()),
            sa.Column("after_data", sa.JSON()),
            sa.Column("reason", sa.Text()),
            sa.Column("ip_address", sa.String(64)),
            sa.Column("user_agent", sa.String(255)),
            sa.Column("request_id", sa.String(128)),
            sa.Column("metadata", sa.JSON()),
        ),
        "data_privacy_requests": (
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("request_type", postgresql.ENUM(
                "account_deletion", "data_export", "data_rectification",
                name="dataprivacyrequesttype", create_type=False,
            ), nullable=False),
            sa.Column("status", postgresql.ENUM(
                "pending", "in_review", "resolved", "rejected",
                name="dataprivacyrequeststatus", create_type=False,
            ), nullable=False),
            sa.Column("message", sa.Text()),
            sa.Column("admin_response", sa.Text()),
            sa.Column("resolved_by", sa.Integer(), sa.ForeignKey("users.id")),
            sa.Column("resolved_at", sa.DateTime(timezone=True)),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True)),
            sa.Column("deleted_at", sa.DateTime(timezone=True)),
            sa.Column("last_modified_by", sa.Integer()),
        ),
        "driver_payouts": (
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("payment_id", sa.Integer(), sa.ForeignKey("payments.id"), nullable=False, unique=True),
            sa.Column("freight_id", sa.Integer(), sa.ForeignKey("freight_requests.id"), nullable=False, unique=True),
            sa.Column("driver_id", sa.Integer(), sa.ForeignKey("drivers.id"), nullable=False),
            sa.Column("amount", sa.Float(), nullable=False),
            sa.Column("status", postgresql.ENUM(
                "pending", "scheduled", "paid", "failed", name="driverpayoutstatus", create_type=False,
            ), nullable=False),
            sa.Column("scheduled_for", sa.DateTime(timezone=True)),
            sa.Column("paid_at", sa.DateTime(timezone=True)),
            sa.Column("transfer_reference", sa.String()),
            sa.Column("note", sa.String()),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True)),
            sa.Column("last_modified_by", sa.Integer()),
        ),
        "driver_review_audits": (
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("driver_id", sa.Integer(), sa.ForeignKey("drivers.id"), nullable=False),
            sa.Column("admin_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("action", sa.String(32), nullable=False),
            sa.Column("status_before", sa.String(32), nullable=False),
            sa.Column("status_after", sa.String(32), nullable=False),
            sa.Column("reason", sa.String()),
            sa.Column("documents_snapshot", sa.JSON(), nullable=False),
            sa.Column("vehicle_snapshot", sa.JSON()),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        ),
        "password_reset_tokens": (
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("token_hash", sa.String(64), nullable=False),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("used_at", sa.DateTime(timezone=True)),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        ),
        "user_consents": (
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("consent_type", sa.String(80), nullable=False),
            sa.Column("version", sa.String(32), nullable=False),
            sa.Column("ip_address", sa.String(64)),
            sa.Column("user_agent", sa.String(255)),
            sa.Column("accepted_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        ),
    }


def _columns():
    timestamp = sa.DateTime(timezone=True)
    return {
        "users": (sa.Column("deleted_at", timestamp), sa.Column("last_modified_by", sa.Integer())),
        "drivers": tuple(sa.Column(name, sa.String()) for name in (
            "profile_image_url", "license_image_url", "vehicle_doc_url", "circulation_permit_url",
            "technical_review_url", "soap_url", "rejection_reason",
        )) + tuple(sa.Column(name, timestamp) for name in (
            "submitted_at", "vehicle_doc_expiry", "circulation_permit_expiry", "technical_review_expiry",
            "soap_expiry", "documents_retention_until", "documents_deleted_at", "updated_at", "deleted_at",
        )) + (sa.Column("last_modified_by", sa.Integer()),),
        "vehicles": (
            sa.Column("updated_at", timestamp), sa.Column("deleted_at", timestamp),
            sa.Column("last_modified_by", sa.Integer()),
        ),
        "freight_requests": tuple(sa.Column(name, sa.String()) for name in (
            "pickup_photo_ref", "delivery_photo_ref", "delivery_pin_hash",
        )) + tuple(sa.Column(name, timestamp) for name in (
            "pickup_photo_uploaded_at", "delivery_photo_uploaded_at", "delivery_pin_generated_at",
            "delivery_pin_verified_at", "updated_at", "deleted_at",
        )) + (
            sa.Column("last_modified_by", sa.Integer()),
            sa.Column("delivery_pin_failed_attempts", sa.Integer(), nullable=False, server_default=sa.text("0")),
        ),
        "payments": (
            sa.Column("updated_at", timestamp), sa.Column("deleted_at", timestamp),
            sa.Column("last_modified_by", sa.Integer()),
        ),
        "data_privacy_requests": (
            sa.Column("deleted_at", timestamp), sa.Column("last_modified_by", sa.Integer()),
        ),
    }


def upgrade() -> None:
    bind = op.get_bind()
    op.execute("SET LOCAL lock_timeout = '5s'")
    tables = set(sa.inspect(bind).get_table_names(schema="public"))
    for name, columns in _tables().items():
        if name not in tables:
            for column in columns:
                if isinstance(column.type, postgresql.ENUM):
                    column.type.create(bind, checkfirst=True)
            op.create_table(name, *columns, schema="public")

    for name, columns in _columns().items():
        existing = {column["name"] for column in sa.inspect(bind).get_columns(name, schema="public")}
        for column in columns:
            if column.name not in existing:
                op.add_column(name, column, schema="public")

    indexed = {
        "audit_events": ("id", "occurred_at", "actor_user_id", "entity_type", "entity_id", "event_type", "request_id"),
        "data_privacy_requests": ("id", "user_id", "request_type", "status"),
        "driver_payouts": ("id", "driver_id", "status"),
        "driver_review_audits": ("id", "driver_id", "admin_id"),
        "password_reset_tokens": ("id", "user_id", "token_hash"),
        "user_consents": ("id", "user_id"),
    }
    for table, columns in indexed.items():
        existing = {index["name"] for index in sa.inspect(bind).get_indexes(table, schema="public")}
        for column in columns:
            name = f"ix_{table}_{column}"
            if name not in existing:
                op.create_index(name, table, [column], unique=column == "token_hash", schema="public")

    # All application-owned tables are private; preserve owner access and other schemas.
    op.execute("""
        DO $$
        DECLARE
            table_item text;
            api_role text;
            sequence_name text;
            column_names text;
        BEGIN
            FOREACH table_item IN ARRAY ARRAY[
                'users', 'drivers', 'vehicles', 'freight_requests', 'payments', 'ratings',
                'notifications', 'trip_status_history', 'freight_pricing_snapshots',
                'freight_price_quotes', 'freight_chat_messages', 'freight_driver_declines',
                'freight_cargo_photos', 'trip_feedback', 'audit_events', 'data_privacy_requests',
                'driver_payouts', 'driver_review_audits', 'password_reset_tokens', 'user_consents'
            ] LOOP
                EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_item);
                sequence_name := pg_get_serial_sequence(format('public.%I', table_item), 'id');
                SELECT string_agg(quote_ident(attname), ', ' ORDER BY attnum) INTO column_names
                FROM pg_attribute WHERE attrelid = format('public.%I', table_item)::regclass
                    AND attnum > 0 AND NOT attisdropped;
                FOREACH api_role IN ARRAY ARRAY['PUBLIC', 'anon', 'authenticated'] LOOP
                    IF api_role = 'PUBLIC' OR EXISTS (SELECT 1 FROM pg_roles WHERE rolname = api_role) THEN
                        EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE public.%I FROM %s',
                            table_item, CASE WHEN api_role = 'PUBLIC' THEN 'PUBLIC' ELSE quote_ident(api_role) END);
                        EXECUTE format('REVOKE ALL PRIVILEGES (%s) ON TABLE public.%I FROM %s',
                            column_names, table_item,
                            CASE WHEN api_role = 'PUBLIC' THEN 'PUBLIC' ELSE quote_ident(api_role) END);
                        IF sequence_name IS NOT NULL THEN
                            EXECUTE format('REVOKE ALL PRIVILEGES ON SEQUENCE %s FROM %s',
                                sequence_name, CASE WHEN api_role = 'PUBLIC' THEN 'PUBLIC' ELSE quote_ident(api_role) END);
                        END IF;
                    END IF;
                END LOOP;
            END LOOP;
        END $$
    """)


def downgrade() -> None:
    # Rolling back application code must not delete payments, consent or audit data.
    pass
