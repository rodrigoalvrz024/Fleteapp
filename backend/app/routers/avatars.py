"""Private account photos; independent of driver verification documents."""

import logging

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.core.rate_limit import check_rate_limit
from app.core.request_limits import RequestBodyLimitMiddleware
from app.core.security import get_current_user
from app.database import get_db
from app.models.user import User
from app.routers.users import _user_response_with_legal_status
from app.schemas.user import UserResponse
from app.services.audit_service import record_audit_event
from app.services.storage_service import (
    delete_private_document, is_user_avatar_ref, stream_private_document, upload_user_avatar,
)

router = APIRouter(prefix="/users", tags=["Usuarios"])
logger = logging.getLogger(__name__)


class AvatarBodyLimitMiddleware(RequestBodyLimitMiddleware):
    def __init__(self, app):
        super().__init__(app, max_bytes=6 * 1024 * 1024, max_buffered_requests=8)

    async def __call__(self, scope, receive, send):
        if scope['type'] == 'http' and scope.get('path', '').rstrip('/') == '/users/me/avatar':
            await super().__call__(scope, receive, send)
        else:
            await self.app(scope, receive, send)


def _lock_avatar_user(db, user_id, password_hash, generation):
    if db.bind.dialect.name == "postgresql":
        db.execute(text("SET LOCAL lock_timeout = '5s'"))
    try:
        user = db.query(User).filter(User.id == user_id).populate_existing().with_for_update().first()
    except OperationalError as exc:
        if getattr(exc.orig, "pgcode", None) == "55P03":
            raise HTTPException(409, "Hay otra operacion en curso. Intenta nuevamente.") from None
        raise
    # The live pilot predates session_version; newer schemas also check it.
    if (not user or not user.is_active or user.deleted_at is not None
            or user.hashed_password != password_hash
            or getattr(user, "session_version", None) != generation):
        raise HTTPException(401, "Sesion no disponible", headers={"WWW-Authenticate": "Bearer"})
    return user


@router.post("/me/avatar", response_model=UserResponse)
async def update_avatar(
    request: Request,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    user_id = current_user.id
    password_hash = current_user.hashed_password
    generation = getattr(current_user, "session_version", None)
    check_rate_limit(request, scope="user-avatar-upload", identifier=str(user_id),
                     max_attempts=10, window_seconds=3600)
    reference = await upload_user_avatar(file, user_id)
    try:
        current_user = _lock_avatar_user(db, user_id, password_hash, generation)
        previous = current_user.avatar_url
        current_user.avatar_url = reference
        current_user.last_modified_by = user_id
        record_audit_event(db, actor=current_user, entity_type="user",
                           entity_id=user_id, event_type="user.avatar_updated",
                           after_data={"has_avatar": True}, request=request)
        db.flush()
        response = _user_response_with_legal_status(db, current_user)
        db.commit()
    except Exception:
        db.rollback()
        # A commit failure can be ambiguous. Never delete a possibly attached photo.
        logger.warning("Avatar attachment failed; private orphan reconciliation may be required")
        raise
    if previous != reference and is_user_avatar_ref(previous, user_id):
        try:
            await run_in_threadpool(delete_private_document, previous)
        except Exception:
            logger.warning("Detached avatar cleanup pending")
    return response


@router.get("/me/avatar")
def get_avatar(current_user: User = Depends(get_current_user)):
    if current_user.deleted_at is not None or not is_user_avatar_ref(current_user.avatar_url, current_user.id):
        raise HTTPException(404, "Foto de perfil no disponible")
    return stream_private_document(current_user.avatar_url)
