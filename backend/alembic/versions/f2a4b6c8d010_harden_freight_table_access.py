"""deny direct Supabase API access to recent backend-owned freight tables

Revision ID: f2a4b6c8d010
Revises: e1f0a2b3c4d5
Create Date: 2026-09-07
"""

from alembic import op


revision = "f2a4b6c8d010"
down_revision = "e1f0a2b3c4d5"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # FastAPI uses the table owner. Do not FORCE RLS or grant client policies.
    op.execute(
        """
        DO $$
        DECLARE
            table_item text;
            api_role text;
            sequence_name text;
        BEGIN
            FOREACH table_item IN ARRAY ARRAY[
                'freight_cargo_photos',
                'freight_chat_messages',
                'freight_driver_declines',
                'trip_feedback'
            ] LOOP
                EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_item);
                EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE public.%I FROM PUBLIC', table_item);
                sequence_name := pg_get_serial_sequence(format('public.%I', table_item), 'id');
                IF sequence_name IS NOT NULL THEN
                    EXECUTE format('REVOKE ALL PRIVILEGES ON SEQUENCE %s FROM PUBLIC', sequence_name);
                END IF;

                FOREACH api_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
                    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = api_role) THEN
                        EXECUTE format(
                            'REVOKE ALL PRIVILEGES ON TABLE public.%I FROM %I',
                            table_item, api_role
                        );
                        IF sequence_name IS NOT NULL THEN
                            EXECUTE format(
                                'REVOKE ALL PRIVILEGES ON SEQUENCE %s FROM %I',
                                sequence_name, api_role
                            );
                        END IF;
                    END IF;
                END LOOP;
            END LOOP;
        END $$
        """
    )


def downgrade() -> None:
    # Application rollback must not reopen direct access or disable protection.
    pass
