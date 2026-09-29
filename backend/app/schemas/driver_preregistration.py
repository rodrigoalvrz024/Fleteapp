import re
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

CONSENT_VERSION = "preregistro-2026-09-v1"


class DriverPreregistrationCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    full_name: str = Field(min_length=3, max_length=100)
    email: EmailStr = Field(max_length=254)
    phone: str = Field(min_length=9, max_length=24)
    commune: str = Field(min_length=2, max_length=80)
    vehicle_type: Literal["camioneta", "furgon", "camion", "otro"]
    availability: Literal["semana", "fin_semana", "ambas"] | None = None
    contact_consent: Literal[True]
    marketing_consent: bool = False
    consent_version: Literal["preregistro-2026-09-v1"]
    website: str = Field(default="", max_length=200)

    @field_validator("full_name", "commune")
    @classmethod
    def clean_text(cls, value):
        if any(ord(char) < 32 or ord(char) == 127 for char in value):
            raise ValueError("Texto invalido")
        return " ".join(value.split())

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value):
        return str(value).lower()

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, value):
        if not re.fullmatch(r"[+\d ()-]+", value):
            raise ValueError("Celular chileno invalido")
        digits = re.sub(r"\D", "", value)
        if re.fullmatch(r"9\d{8}", digits):
            digits = "56" + digits
        if not re.fullmatch(r"569\d{8}", digits):
            raise ValueError("Ingresa un celular chileno")
        return "+" + digits
