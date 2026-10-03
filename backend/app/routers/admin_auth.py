from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import Field
from sqlalchemy.orm import Session

from app.core.rate_limit import check_rate_limit
from app.core.config import settings
from app.core.security import admin_credential_stamp, create_access_token, hash_password, require_role, verify_password
from app.database import get_db
from app.models.admin_second_factor import AdminSecondFactor
from app.models.user import User, UserRole
from app.schemas.user import UserLogin, TokenResponse, MessageResponse
from app.routers.auth import _user_response, _record_updated_consents
from app.services.admin_mfa_service import verify_factor
from app.services.audit_service import record_audit_event
from app.services.row_lock_service import lock_first

router = APIRouter(prefix="/auth/admin", tags=["Administracion segura"])
DUMMY_HASH = hash_password("synthetic-invalid-admin-password")


class AdminLogin(UserLogin):
    code: str = Field(pattern=r"^[0-9]{6}$", min_length=6, max_length=6, repr=False)
    accepted_terms_version: str | None = Field(default=None, max_length=40)
    accepted_privacy_version: str | None = Field(default=None, max_length=40)


@router.post("/login", response_model=TokenResponse)
def login(data: AdminLogin, request: Request, db: Session = Depends(get_db)):
    check_rate_limit(request, scope="admin-login-ip", max_attempts=30, window_seconds=900)
    check_rate_limit(request, scope="admin-login-account", identifier=data.email,
                     max_attempts=8, window_seconds=900)
    try:
        user = lock_first(db.query(User).filter(User.email == data.email).populate_existing())
        valid = verify_password(data.password, user.hashed_password if user else DUMMY_HASH)
        if not valid or not user or user.role != UserRole.admin or not user.is_active or user.deleted_at:
            raise HTTPException(401, "No se pudo verificar el acceso administrativo")
        factor = lock_first(db.query(AdminSecondFactor).filter(
            AdminSecondFactor.user_id == user.id).populate_existing())
        now = datetime.now(timezone.utc)
        verify_factor(db, factor, data.code, now)
        response_user = _user_response(db, user)
        if response_user.legal_reacceptance_required:
            if (data.accepted_terms_version != settings.ADMIN_TERMS_VERSION
                    or data.accepted_privacy_version != settings.ADMIN_PRIVACY_VERSION):
                raise HTTPException(403, "Revisa y acepta los documentos legales vigentes del portal")
            _record_updated_consents(db, user, request)
            response_user = _user_response(db, user)
        user.last_login_at = now
        user.last_seen_at = now
        user.last_seen_screen = "/auth/admin/login"
        record_audit_event(db, actor=user, entity_type="user", entity_id=user.id,
                          event_type="auth.admin_mfa_login", request=request)
        token = create_access_token({"sub": str(user.id), "role": "admin",
            "session_version": user.session_version, "admin_mfa": True,
            "admin_credentials": admin_credential_stamp(user),
            "admin_mfa_at": int(now.timestamp())}, expires_delta=timedelta(minutes=29))
        response = TokenResponse(access_token=token, user=response_user)
        db.commit()
        return response
    except Exception:
        db.rollback()
        raise


@router.post("/logout", response_model=MessageResponse)
def logout(request: Request, actor=Depends(require_role("admin")), db: Session = Depends(get_db)):
    user_id, version = actor.id, actor.session_version
    try:
        user = lock_first(db.query(User).filter(User.id == user_id).populate_existing())
        if not user or user.session_version != version or user.role != UserRole.admin or not user.is_active or user.deleted_at:
            raise HTTPException(401, "Sesion no disponible")
        user.session_version += 1
        record_audit_event(db, actor=user, entity_type="user", entity_id=user.id,
                          event_type="auth.admin_logout", request=request)
        db.commit()
        return MessageResponse(message="Sesiones administrativas cerradas")
    except Exception:
        db.rollback()
        raise
