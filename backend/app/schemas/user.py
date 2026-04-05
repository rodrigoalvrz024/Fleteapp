from pydantic import BaseModel, EmailStr, field_validator
from typing import Optional
from datetime import datetime
from app.models.user import UserRole

class UserCreate(BaseModel):
    email: EmailStr
    phone: str
    full_name: str
    password: str
    role: UserRole = UserRole.client

    @field_validator("password")
    def password_strength(cls, v):
        if len(v) < 8:
            raise ValueError("La contraseña debe tener al menos 8 caracteres")
        return v

    @field_validator("phone")
    def phone_format(cls, v):
        digits = v.replace("+", "").replace(" ", "")
        if not digits.isdigit() or len(digits) < 9:
            raise ValueError("Teléfono inválido")
        return v

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    phone: Optional[str] = None
    avatar_url: Optional[str] = None
    fcm_token: Optional[str] = None

class UserResponse(BaseModel):
    id: int
    email: str
    phone: str
    full_name: str
    role: UserRole
    is_active: bool
    avatar_url: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse