from pydantic import BaseModel, field_validator
from typing import Optional
from datetime import datetime

class RatingCreate(BaseModel):
    freight_id: int
    score: float
    comment: Optional[str] = None

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