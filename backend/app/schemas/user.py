import enum
import re
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.models.user import UserRole


class PublicUserRole(str, enum.Enum):
    client = "client"
    driver = "driver"


def _normalize_phone(value: str) -> str:
    digits = re.sub(r"[^0-9]", "", value)
    if not 9 <= len(digits) <= 15:
        raise ValueError("Telefono invalido")
    return digits


def _validate_password(value: str) -> str:
    if not 8 <= len(value) <= 72:
        raise ValueError("La contrasena debe tener entre 8 y 72 caracteres")
    return value


class UserCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    email: EmailStr
    phone: str
    full_name: str = Field(min_length=2, max_length=120)
    password: str
    role: PublicUserRole = PublicUserRole.client
    accepts_terms: bool = False
    accepts_privacy: bool = False
    accepts_driver_documents: bool = False

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: EmailStr) -> str:
        return str(value).lower()

    @field_validator("password")
    @classmethod
    def password_strength(cls, value: str) -> str:
        return _validate_password(value)

    @field_validator("phone")
    @classmethod
    def phone_format(cls, value: str) -> str:
        return _normalize_phone(value)


class UserLogin(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    email: EmailStr
    password: str = Field(min_length=1, max_length=72)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: EmailStr) -> str:
        return str(value).lower()


class LegalUpdateAcceptance(BaseModel):
    model_config = ConfigDict(extra="forbid")

    accepts_terms: bool = False
    accepts_privacy: bool = False


class PasswordResetRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    email: EmailStr

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: EmailStr) -> str:
        return str(value).lower()


class PasswordResetConfirm(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    token: str = Field(min_length=32, max_length=512)
    new_password: str

    @field_validator("new_password")
    @classmethod
    def password_strength(cls, value: str) -> str:
        return _validate_password(value)


class MessageResponse(BaseModel):
    message: str


class UserUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    full_name: Optional[str] = Field(default=None, min_length=2, max_length=120)
    phone: Optional[str] = None
    avatar_url: Optional[str] = Field(default=None, max_length=2048)
    fcm_token: Optional[str] = Field(default=None, max_length=4096)

    @field_validator("phone")
    @classmethod
    def phone_format(cls, value: Optional[str]) -> Optional[str]:
        return _normalize_phone(value) if value is not None else value

    @field_validator("avatar_url")
    @classmethod
    def avatar_url_format(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return value
        if not value.startswith("https://"):
            raise ValueError("La imagen de perfil debe usar HTTPS")
        return value


class UserResponse(BaseModel):
    id: int
    email: str
    phone: str
    full_name: str
    role: UserRole
    is_active: bool
    avatar_url: Optional[str]
    created_at: datetime
    legal_reacceptance_required: bool = False

    class Config:
        from_attributes = True


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse
