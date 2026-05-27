from fastapi import APIRouter, Depends, HTTPException
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

router = APIRouter(prefix="/users", tags=["Usuarios"])

@router.get("/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user)):
    return current_user

@router.put("/me", response_model=UserResponse)
def update_me(data: UserUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    for field, value in data.model_dump(exclude_none=True).items():
        setattr(current_user, field, value)
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
    )
    db.add(privacy_request)
    db.commit()
    db.refresh(privacy_request)
    return privacy_request
