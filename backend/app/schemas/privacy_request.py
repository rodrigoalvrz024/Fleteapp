from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from app.models.data_privacy_request import (
    DataPrivacyRequestStatus,
    DataPrivacyRequestType,
)


class PrivacyRequestCreate(BaseModel):
    request_type: DataPrivacyRequestType
    message: Optional[str] = Field(default=None, max_length=1000)


class PrivacyRequestAdminUpdate(BaseModel):
    status: DataPrivacyRequestStatus
    admin_response: Optional[str] = Field(default=None, max_length=1000)


class PrivacyRequestResponse(BaseModel):
    id: int
    user_id: int
    request_type: DataPrivacyRequestType
    status: DataPrivacyRequestStatus
    message: Optional[str] = None
    admin_response: Optional[str] = None
    resolved_by: Optional[int] = None
    resolved_at: Optional[datetime] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True
