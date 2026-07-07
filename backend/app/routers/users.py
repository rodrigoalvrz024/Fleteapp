from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.data_privacy_request import (
    DataPrivacyRequest,
    DataPrivacyRequestStatus,
)
from app.models.user import User
from app.schemas.privacy_request import PrivacyRequestCreate, PrivacyRequestResponse
from app.schemas.user import UserResponse, UserUpdate
from app.core.security import get_current_user
from app.services.audit_service import record_audit_event

router = APIRouter(prefix="/users", tags=["Usuarios"])
SENSITIVE_AUDIT_FIELDS = {"fcm_token"}


def _redact_user_audit_data(data: dict) -> dict:
    redacted = data.copy()
    for field in SENSITIVE_AUDIT_FIELDS:
        if field in redacted:
            redacted[field] = "[redacted]" if redacted[field] else None
    return redacted

@router.get("/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user)):
    return current_user

@router.put("/me", response_model=UserResponse)
def update_me(
    data: UserUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    before_data = {
        "full_name": current_user.full_name,
        "phone": current_user.phone,
        "avatar_url": current_user.avatar_url,
        "fcm_token": current_user.fcm_token,
    }
    update_data = data.model_dump(exclude_none=True)
    for field, value in update_data.items():
        setattr(current_user, field, value)
    current_user.last_modified_by = current_user.id
    record_audit_event(
        db,
        actor=current_user,
        entity_type="user",
        entity_id=current_user.id,
        event_type="user.updated",
        before_data=_redact_user_audit_data(before_data),
        after_data=_redact_user_audit_data(update_data),
        request=request,
    )
    db.commit()
    db.refresh(current_user)
    return current_user


@router.get("/me/privacy-requests", response_model=list[PrivacyRequestResponse])
def list_my_privacy_requests(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return (
        db.query(DataPrivacyRequest)
        .filter(DataPrivacyRequest.user_id == current_user.id)
        .order_by(DataPrivacyRequest.created_at.desc())
        .all()
    )


@router.post(
    "/me/privacy-requests",
    response_model=PrivacyRequestResponse,
    status_code=201,
)
def create_my_privacy_request(
    data: PrivacyRequestCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    active_request = (
        db.query(DataPrivacyRequest)
        .filter(
            DataPrivacyRequest.user_id == current_user.id,
            DataPrivacyRequest.request_type == data.request_type,
            DataPrivacyRequest.status.in_(
                [
                    DataPrivacyRequestStatus.pending,
                    DataPrivacyRequestStatus.in_review,
                ]
            ),
        )
        .first()
    )
    if active_request:
        raise HTTPException(
            status_code=400,
            detail="Ya tienes una solicitud de este tipo en revision",
        )

    privacy_request = DataPrivacyRequest(
        user_id=current_user.id,
        request_type=data.request_type,
        message=data.message.strip() if data.message else None,
        last_modified_by=current_user.id,
    )
    db.add(privacy_request)
    db.flush()
    record_audit_event(
        db,
        actor=current_user,
        entity_type="data_privacy_request",
        entity_id=privacy_request.id,
        event_type="privacy_request.created",
        after_data={
            "request_type": data.request_type.value,
            "status": DataPrivacyRequestStatus.pending.value,
        },
        request=request,
    )
    db.commit()
    db.refresh(privacy_request)
    return privacy_request
