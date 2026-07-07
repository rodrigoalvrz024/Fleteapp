-- FleteApp Supabase hardening
--
-- Purpose:
--   Keep Supabase/PostgREST client roles from reading or mutating backend-owned
--   tables directly. Cloud Run remains the application gateway to Postgres.
--
-- Notes:
--   - This enables RLS but does not FORCE RLS, so the backend direct database
--     connection can continue to operate normally.
--   - No permissive policies are created. For anon/authenticated Supabase API
--     clients this is "deny by default".

BEGIN;

DO $$
DECLARE
    table_item text;
    app_tables text[] := ARRAY[
        'audit_events',
        'data_privacy_requests',
        'driver_payouts',
        'driver_review_audits',
        'drivers',
        'freight_requests',
        'notifications',
        'password_reset_tokens',
        'payments',
        'ratings',
        'trip_status_history',
        'user_consents',
        'users',
        'vehicles'
    ];
BEGIN
    FOREACH table_item IN ARRAY app_tables LOOP
        IF to_regclass(format('public.%I', table_item)) IS NOT NULL THEN
            EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_item);

            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
                EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE public.%I FROM anon', table_item);
            END IF;

            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
                EXECUTE format('REVOKE ALL PRIVILEGES ON TABLE public.%I FROM authenticated', table_item);
            END IF;

            EXECUTE format(
                'COMMENT ON TABLE public.%I IS %L',
                table_item,
                'Backend-owned FleteApp table. RLS enabled to deny direct Supabase client access by default.'
            );
        END IF;
    END LOOP;
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM anon;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM authenticated;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM authenticated;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM authenticated;
    END IF;
END $$;

COMMIT;
