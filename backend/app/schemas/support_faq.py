import unicodedata
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class FAQWrite(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    slug: str = Field(min_length=3, max_length=80, pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
    category: Literal["requests", "payments", "account", "safety"]
    question: str = Field(min_length=5, max_length=200)
    answer: str = Field(min_length=10, max_length=4000)
    audience: Literal["all", "client", "driver"] = "all"
    published: bool = False
    sort_order: int = Field(default=0, ge=0, le=10000)

    @field_validator("question", "answer")
    @classmethod
    def plain_text(cls, value):
        if any(unicodedata.category(c).startswith("C") and c != "\n" for c in value):
            raise ValueError("Usa texto sin caracteres de control")
        if "<" in value or ">" in value:
            raise ValueError("Usa texto sin HTML")
        return value


class FAQUpdate(FAQWrite):
    version: int = Field(ge=1)


class FAQResponse(FAQWrite):
    model_config = ConfigDict(from_attributes=True)
    id: int
    version: int
    updated_at: datetime
