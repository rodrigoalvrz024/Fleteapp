from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class TripFeedbackCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    overall_score: int = Field(ge=1, le=5)
    answers: dict[str, int] = Field(min_length=5, max_length=5)
    comment: str | None = Field(default=None, max_length=600)

    @field_validator("answers")
    @classmethod
    def scores_are_valid(cls, value: dict[str, int]) -> dict[str, int]:
        if any(not isinstance(score, int) or score < 1 or score > 5 for score in value.values()):
            raise ValueError("Cada respuesta debe tener un puntaje entre 1 y 5")
        return value


class TripFeedbackResponse(BaseModel):
    id: int
    freight_id: int
    recipient_role: Literal["client", "driver"]
    overall_score: float
    answers: dict[str, int]
    comment: str | None = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
