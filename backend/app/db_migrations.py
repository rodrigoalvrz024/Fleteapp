from sqlalchemy import text


STARTUP_MIGRATIONS = (
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS service_type VARCHAR(32)
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS extra_stops INTEGER NOT NULL DEFAULT 0
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS pickup_floor INTEGER
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS delivery_floor INTEGER
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS pickup_has_elevator BOOLEAN NOT NULL DEFAULT TRUE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS delivery_has_elevator BOOLEAN NOT NULL DEFAULT TRUE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS estimated_duration_minutes DOUBLE PRECISION
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS actual_distance_km DOUBLE PRECISION
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS recommended_vehicle_type VARCHAR(32)
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS selected_vehicle_type VARCHAR(32)
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS pricing_version VARCHAR(32)
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS pricing_type VARCHAR(32) NOT NULL DEFAULT 'automatic'
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS requires_manual_quote BOOLEAN NOT NULL DEFAULT FALSE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS route_provider VARCHAR(40)
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS route_calculated_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS quote_expires_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS actual_vehicle_id INTEGER
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS requested_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS price_estimated_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS customer_confirmed_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS driver_assigned_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS driver_accepted_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS driver_arrived_pickup_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS trip_started_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS driver_arrived_destination_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS trip_completed_at TIMESTAMP WITH TIME ZONE
    """,
    """
    CREATE INDEX IF NOT EXISTS ix_freight_requests_actual_vehicle_id
    ON freight_requests (actual_vehicle_id)
    """,
    """
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS last_modified_by INTEGER
    """,
    """
    ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS last_modified_by INTEGER
    """,
    """
    ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS documents_retention_until TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS documents_deleted_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS vehicle_doc_expiry TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS circulation_permit_expiry TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS technical_review_expiry TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE drivers
    ADD COLUMN IF NOT EXISTS soap_expiry TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS last_modified_by INTEGER
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS pickup_photo_ref VARCHAR
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS pickup_photo_uploaded_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS delivery_photo_ref VARCHAR
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS delivery_photo_uploaded_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS delivery_pin_hash VARCHAR
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS delivery_pin_generated_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS delivery_pin_verified_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS delivery_pin_failed_attempts INTEGER NOT NULL DEFAULT 0
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS driver_location_lat DOUBLE PRECISION
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS driver_location_lng DOUBLE PRECISION
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS driver_location_accuracy_m DOUBLE PRECISION
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS driver_location_heading DOUBLE PRECISION
    """,
    """
    ALTER TABLE freight_requests
    ADD COLUMN IF NOT EXISTS driver_location_updated_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS last_modified_by INTEGER
    """,
    """
    ALTER TABLE vehicles
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE vehicles
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE vehicles
    ADD COLUMN IF NOT EXISTS last_modified_by INTEGER
    """,
    """
    ALTER TABLE data_privacy_requests
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE
    """,
    """
    ALTER TABLE data_privacy_requests
    ADD COLUMN IF NOT EXISTS last_modified_by INTEGER
    """,
    """
    INSERT INTO driver_payouts (
        payment_id,
        freight_id,
        driver_id,
        amount,
        status,
        created_at
    )
    SELECT
        payments.id,
        freight_requests.id,
        freight_requests.driver_id,
        freight_requests.driver_receives,
        'pending',
        NOW()
    FROM payments
    JOIN freight_requests ON freight_requests.id = payments.freight_id
    WHERE payments.status::text = 'authorized'
      AND freight_requests.driver_id IS NOT NULL
      AND freight_requests.driver_receives IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM driver_payouts
          WHERE driver_payouts.payment_id = payments.id
      )
    """,
    """
    CREATE INDEX IF NOT EXISTS ix_freight_requests_client_created
    ON freight_requests (client_id, created_at DESC)
    """,
    """
    CREATE INDEX IF NOT EXISTS ix_freight_requests_driver_created
    ON freight_requests (driver_id, created_at DESC)
    """,
    """
    CREATE INDEX IF NOT EXISTS ix_freight_requests_status_driver
    ON freight_requests (status, driver_id)
    """,
    """
    CREATE INDEX IF NOT EXISTS ix_trip_status_history_freight_created
    ON trip_status_history (freight_id, created_at)
    """,
)


def run_startup_migrations(engine) -> None:
    with engine.begin() as conn:
        for statement in STARTUP_MIGRATIONS:
            conn.execute(text(statement))
