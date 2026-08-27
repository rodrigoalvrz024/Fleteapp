from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.config import settings


class ChatMessageCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    message_text: str = Field(min_length=1)
    message_type: Literal["text"] = "text"

    @field_validator("message_text")
    @classmethod
    def reject_control_characters(cls, value: str) -> str:
        if any(ord(character) < 32 and character not in "\n\t" for character in value):
            raise ValueError("El mensaje contiene caracteres no validos")
        if not value.strip():
            raise ValueError("El mensaje no puede estar vacio")
        if len(value) > settings.CHAT_MESSAGE_MAX_LENGTH:
            raise ValueError(
                f"El mensaje no puede superar {settings.CHAT_MESSAGE_MAX_LENGTH} caracteres"
            )
        return value


class ChatImageCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    caption: str = ""

    @field_validator("caption")
    @classmethod
    def validate_caption(cls, value: str) -> str:
        if any(ord(character) < 32 and character not in "\n\t" for character in value):
            raise ValueError("El mensaje contiene caracteres no validos")
        if len(value) > settings.CHAT_MESSAGE_MAX_LENGTH:
            raise ValueError(
                f"El mensaje no puede superar {settings.CHAT_MESSAGE_MAX_LENGTH} caracteres"
            )
        return value


class ChatMessageResponse(BaseModel):
    id: int
    freight_id: int
    sender_user_id: int
    receiver_user_id: int
    message_text: str
    message_type: str
    attachment_view_path: str | None = None
    attachment_content_type: str | None = None
    attachment_size_bytes: int | None = None
    created_at: datetime
    read_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)


class ChatPeerResponse(BaseModel):
    full_name: str
    role: Literal["client", "driver"]
    avatar_url: str | None = None


class ChatSummaryResponse(BaseModel):
    freight_id: int
    is_writable: bool
    status: str
    unread_count: int
    max_message_length: int
    peer: ChatPeerResponse


class ChatReadResponse(BaseModel):
    marked_count: int


class AdminChatReviewRequest(BaseModel):
    """A narrowly scoped, auditable reason for a compliance review."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    reason: str = Field(min_length=12, max_length=600)

    @field_validator("reason")
    @classmethod
    def validate_reason(cls, value: str) -> str:
        if any(ord(character) < 32 and character not in "\n\t" for character in value):
            raise ValueError("El motivo contiene caracteres no validos")
        if not value.strip():
            raise ValueError("Debes indicar el motivo de la revision")
        return value


class AdminChatReviewResponse(BaseModel):
    freight_id: int
    status: str
    client_user_id: int
    driver_user_id: int
    client: ChatPeerResponse
    driver: ChatPeerResponse
    messages: list[ChatMessageResponse]
    has_more: bool
    read_only: bool = True
