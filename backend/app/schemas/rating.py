from pydantic import BaseModel, ConfigDict, Field, field_validator
from typing import Optional
from datetime import datetime

class RatingCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    freight_id: int = Field(gt=0)
    score: float = Field(allow_inf_nan=False)
    comment: Optional[str] = Field(default=None, max_length=1000)

    @field_validator("score")
    def score_range(cls, v):
        if not (1.0 <= v <= 5.0):
            raise ValueError("El puntaje debe estar entre 1 y 5")
        return round(v * 2) / 2

class RatingResponse(BaseModel):
    id: int
    freight_id: int
    score: float
    comment: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True
