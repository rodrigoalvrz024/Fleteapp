from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    APP_ENV: str = "production"
    DATABASE_URL: str
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    CORS_ORIGINS: str = (
        "https://fleteapp-8d8f7.web.app,"
        "https://fleteapp-public-8d8f7.web.app,"
        "http://127.0.0.1:8090,"
        "http://localhost:8090,"
        "http://127.0.0.1:3000,"
        "http://localhost:3000,"
        "http://127.0.0.1:3001,"
        "http://localhost:3001,"
        "http://127.0.0.1:8000,"
        "http://localhost:8000"
    )
    TRANSBANK_COMMERCE_CODE: str = ""
    TRANSBANK_API_KEY: str = ""
    TRANSBANK_ENVIRONMENT: str = "integration"
    ALLOW_SIMULATED_PAYMENTS: bool = False
    FIREBASE_SERVER_KEY: str = ""
    GOOGLE_MAPS_KEY: str = ""
    FRONTEND_URL: str = "https://fleteapp-8d8f7.web.app"
    RESEND_API_KEY: str = ""
    EMAIL_FROM: str = "FleteApp <onboarding@resend.dev>"
    ALLOW_PASSWORD_RESET_LINK_LOGS: bool = False
    PASSWORD_RESET_EXPIRE_MINUTES: int = 30
    TERMS_VERSION: str = "2026-05-26"
    PRIVACY_VERSION: str = "2026-05-26"
    DRIVER_DOCUMENTS_BUCKET: str = ""
    DRIVER_DOCUMENT_MAX_MB: int = 5
    DRIVER_DOCUMENT_VIEW_EXPIRE_MINUTES: int = 10
    DRIVER_REJECTED_DOCUMENT_RETENTION_DAYS: int = 90
    FREIGHT_EVIDENCE_MAX_MB: int = 8
    FREIGHT_EVIDENCE_VIEW_EXPIRE_MINUTES: int = 10
    PUBLIC_API_URL: str = ""
    ALLOW_EXTERNAL_DOCUMENT_REFS: bool = False
    ENABLE_DRIVER_PUSH_NOTIFICATIONS: bool = False
    NOTIFICATION_TASKS_ENABLED: bool = False
    GOOGLE_CLOUD_PROJECT: str = ""
    CLOUD_TASKS_LOCATION: str = "us-central1"
    CLOUD_TASKS_QUEUE: str = "freight-notifications"
    CLOUD_TASKS_SERVICE_ACCOUNT: str = ""
    CLOUD_TASKS_TARGET_BASE_URL: str = ""
    CLOUD_TASKS_AUDIENCE: str = ""
    RUN_STARTUP_MIGRATIONS: bool = False
    DB_CONNECT_TIMEOUT_SECONDS: int = 10
    DB_POOL_SIZE: int = 5
    DB_MAX_OVERFLOW: int = 2
    DB_POOL_TIMEOUT_SECONDS: int = 5

    class Config:
        env_file = ".env"

settings = Settings()
