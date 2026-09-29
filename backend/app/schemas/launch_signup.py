from typing import Literal
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator
from app.schemas.driver_preregistration import DriverPreregistrationCreate

CONSENT_VERSION = "lanzamiento-2026-09-v1"


class LaunchSignupCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    full_name: str = Field(min_length=3, max_length=100)
    email: EmailStr = Field(max_length=254)
    phone: str = Field(min_length=9, max_length=24)
    platform: Literal["android", "ios", "ambas"]
    email_consent: bool = False
    whatsapp_consent: bool = False
    consent_version: Literal["lanzamiento-2026-09-v1"]
    website: str = Field(default="", max_length=200)

    @field_validator("full_name")
    @classmethod
    def clean_name(cls, value):
        return DriverPreregistrationCreate.clean_text(value)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value):
        return str(value).lower()

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, value):
        return DriverPreregistrationCreate.normalize_phone(value)

    @model_validator(mode="after")
    def require_channel(self):
        if not (self.email_consent or self.whatsapp_consent):
            raise ValueError("Selecciona al menos un canal para el aviso")
        return self
