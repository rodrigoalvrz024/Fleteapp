import json

from pydantic import model_validator
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    APP_ENV: str = "production"
    DATABASE_URL: str
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    PILOT_MODE: bool = False
    PILOT_ALLOWED_EMAILS: str = ""
    CORS_ORIGINS: str = (
        "https://muvv-dev.web.app,"
        "https://muvv-dev-public.web.app,"
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
    FIREBASE_CREDENTIALS_JSON: str = ""
    GOOGLE_MAPS_KEY: str = ""
    FRONTEND_URL: str = "https://muvv-dev.web.app"
    RESEND_API_KEY: str = ""
    EMAIL_FROM: str = "Muvv <onboarding@resend.dev>"
    PASSWORD_RESET_EXPIRE_MINUTES: int = 30
    TERMS_VERSION: str = "2026-08-26"
    PRIVACY_VERSION: str = "2026-08-26"
    DRIVER_DOCUMENTS_BUCKET: str = ""
    SUPABASE_URL: str = ""
    SUPABASE_SERVICE_ROLE_KEY: str = ""
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
    MAX_REQUEST_BODY_MB: int = 10
    JWT_ISSUER: str = "muvv-api"
    JWT_AUDIENCE: str = "muvv-app"
    PRICING_CONFIG_JSON: str = ""
    PRICING_QUOTE_EXPIRE_MINUTES: int = 10
    PRICING_ROUTE_MAX_RETRIES: int = 2
    CHAT_MESSAGE_MAX_LENGTH: int = 1000
    CHAT_MESSAGE_PAGE_SIZE: int = 80
    CHAT_MESSAGE_MAX_PAGE_SIZE: int = 100
    CHAT_SEND_MAX_MESSAGES_PER_MINUTE: int = 40
    CHAT_IMAGE_MAX_MB: int = 5
    CHAT_IMAGE_VIEW_EXPIRE_MINUTES: int = 10
    CHAT_IMAGE_SEND_MAX_PER_MINUTE: int = 12
    CHAT_ADMIN_REVIEW_MAX_PER_HOUR: int = 30
    CHAT_ADMIN_REVIEW_MESSAGE_LIMIT: int = 200

    class Config:
        env_file = ".env"

    @property
    def is_production(self) -> bool:
        return self.APP_ENV.strip().lower() in {"production", "prod"}

    @property
    def cors_origins(self) -> list[str]:
        origins = [
            origin.strip().rstrip("/")
            for origin in self.CORS_ORIGINS.split(",")
            if origin.strip()
        ]
        if self.is_production:
            origins = [
                origin
                for origin in origins
                if not origin.startswith("http://localhost")
                and not origin.startswith("http://127.0.0.1")
            ]
        return list(dict.fromkeys(origins))

    @property
    def pilot_allowed_emails(self) -> set[str]:
        return {
            email.strip().lower()
            for email in self.PILOT_ALLOWED_EMAILS.split(",")
            if email.strip()
        }

    @model_validator(mode="after")
    def validate_security_configuration(self):
        if self.ALGORITHM != "HS256":
            raise ValueError("ALGORITHM debe ser HS256")
        if not 5 <= self.ACCESS_TOKEN_EXPIRE_MINUTES <= 1440:
            raise ValueError("ACCESS_TOKEN_EXPIRE_MINUTES debe estar entre 5 y 1440")
        if self.MAX_REQUEST_BODY_MB < 1 or self.MAX_REQUEST_BODY_MB > 25:
            raise ValueError("MAX_REQUEST_BODY_MB debe estar entre 1 y 25")
        if not 1 <= self.DRIVER_DOCUMENT_VIEW_EXPIRE_MINUTES <= 60:
            raise ValueError("DRIVER_DOCUMENT_VIEW_EXPIRE_MINUTES debe estar entre 1 y 60")
        if not 1 <= self.FREIGHT_EVIDENCE_VIEW_EXPIRE_MINUTES <= 60:
            raise ValueError("FREIGHT_EVIDENCE_VIEW_EXPIRE_MINUTES debe estar entre 1 y 60")
        if not 1 <= self.PRICING_QUOTE_EXPIRE_MINUTES <= 60:
            raise ValueError("PRICING_QUOTE_EXPIRE_MINUTES debe estar entre 1 y 60")
        if not 0 <= self.PRICING_ROUTE_MAX_RETRIES <= 4:
            raise ValueError("PRICING_ROUTE_MAX_RETRIES debe estar entre 0 y 4")
        if not 1 <= self.CHAT_MESSAGE_MAX_LENGTH <= 4000:
            raise ValueError("CHAT_MESSAGE_MAX_LENGTH debe estar entre 1 y 4000")
        if not 10 <= self.CHAT_MESSAGE_PAGE_SIZE <= 100:
            raise ValueError("CHAT_MESSAGE_PAGE_SIZE debe estar entre 10 y 100")
        if not self.CHAT_MESSAGE_PAGE_SIZE <= self.CHAT_MESSAGE_MAX_PAGE_SIZE <= 100:
            raise ValueError(
                "CHAT_MESSAGE_MAX_PAGE_SIZE debe estar entre CHAT_MESSAGE_PAGE_SIZE y 100"
            )
        if not 1 <= self.CHAT_SEND_MAX_MESSAGES_PER_MINUTE <= 120:
            raise ValueError(
                "CHAT_SEND_MAX_MESSAGES_PER_MINUTE debe estar entre 1 y 120"
            )
        if not 1 <= self.CHAT_IMAGE_MAX_MB <= 8:
            raise ValueError(
                "CHAT_IMAGE_MAX_MB debe estar entre 1 y 8"
            )
        if not 1 <= self.CHAT_IMAGE_VIEW_EXPIRE_MINUTES <= 60:
            raise ValueError(
                "CHAT_IMAGE_VIEW_EXPIRE_MINUTES debe estar entre 1 y 60"
            )
        if not 1 <= self.CHAT_IMAGE_SEND_MAX_PER_MINUTE <= 30:
            raise ValueError(
                "CHAT_IMAGE_SEND_MAX_PER_MINUTE debe estar entre 1 y 30"
            )
        if not 1 <= self.CHAT_ADMIN_REVIEW_MAX_PER_HOUR <= 120:
            raise ValueError(
                "CHAT_ADMIN_REVIEW_MAX_PER_HOUR debe estar entre 1 y 120"
            )
        if not 20 <= self.CHAT_ADMIN_REVIEW_MESSAGE_LIMIT <= 300:
            raise ValueError(
                "CHAT_ADMIN_REVIEW_MESSAGE_LIMIT debe estar entre 20 y 300"
            )
        if self.is_production:
            if len(self.SECRET_KEY) < 32 or self.SECRET_KEY.startswith("change-me"):
                raise ValueError("SECRET_KEY de produccion debe tener al menos 32 caracteres aleatorios")
            if self.ALLOW_SIMULATED_PAYMENTS:
                raise ValueError("Los pagos simulados no se pueden habilitar en produccion")
            if not self.cors_origins:
                raise ValueError("CORS_ORIGINS debe incluir al menos un origen HTTPS en produccion")
            if any(not origin.startswith("https://") for origin in self.cors_origins):
                raise ValueError("CORS_ORIGINS solo puede incluir origenes HTTPS en produccion")
            if self.ALLOW_EXTERNAL_DOCUMENT_REFS:
                raise ValueError("ALLOW_EXTERNAL_DOCUMENT_REFS no se permite en produccion")
            if self.PILOT_MODE and not self.pilot_allowed_emails:
                raise ValueError(
                    "PILOT_ALLOWED_EMAILS debe incluir al menos un correo cuando PILOT_MODE esta activo"
                )
        return self

    @property
    def firebase_push_configured(self) -> bool:
        """Whether Firebase Admin credentials can safely be used for push delivery.

        Push is optional infrastructure. A malformed credential must never make the
        freight API unavailable; delivery is skipped until a valid secret is set.
        """
        if not self.ENABLE_DRIVER_PUSH_NOTIFICATIONS:
            return False
        try:
            credentials = json.loads(self.FIREBASE_CREDENTIALS_JSON)
        except (TypeError, json.JSONDecodeError):
            return False
        return bool(
            credentials.get("type") == "service_account"
            and credentials.get("client_email")
            and credentials.get("private_key")
        )

settings = Settings()
