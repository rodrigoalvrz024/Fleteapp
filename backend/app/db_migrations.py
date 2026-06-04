from sqlalchemy import text


STARTUP_MIGRATIONS = (
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
)


def run_startup_migrations(engine) -> None:
    with engine.begin() as conn:
        for statement in STARTUP_MIGRATIONS:
            conn.execute(text(statement))
