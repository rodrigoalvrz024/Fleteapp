from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DATABASE_URL: str
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080
    CLOUDINARY_CLOUD_NAME: str = ""
    CLOUDINARY_API_KEY: str = ""
    CLOUDINARY_API_SECRET: str = ""
    TRANSBANK_COMMERCE_CODE: str = ""
    TRANSBANK_API_KEY: str = ""
    TRANSBANK_ENVIRONMENT: str = "integration"
    FIREBASE_SERVER_KEY: str = ""
    GOOGLE_MAPS_KEY: str = ""
    FRONTEND_URL: str = "https://fleteapp-8d8f7.web.app"
    RESEND_API_KEY: str = ""
    EMAIL_FROM: str = "FleteApp <onboarding@resend.dev>"
    PASSWORD_RESET_EXPIRE_MINUTES: int = 30

    class Config:
        env_file = ".env"

settings = Settings()
