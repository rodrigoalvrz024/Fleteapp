from typing import Any

from pydantic import BaseModel, Field


class AnalyticsEventCreate(BaseModel):
    event_type: str = Field(min_length=3, max_length=80)
    entity_type: str = Field(min_length=3, max_length=80)
    entity_id: str = Field(min_length=1, max_length=64)
    metadata: dict[str, Any] | None = None


class AnalyticsEventResponse(BaseModel):
    status: str
