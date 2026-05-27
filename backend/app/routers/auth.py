from datetime import datetime, timedelta, timezone
import hashlib
import secrets

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.rate_limit import check_rate_limit
from app.core.security import create_access_token, hash_password, verify_password
from app.database import get_db
from app.models.password_reset import PasswordResetToken
from app.models.user import User, UserRole
from app.models.user_consent import UserConsent
from app.schemas.user import (
    MessageResponse,
    PasswordResetConfirm,
    PasswordResetRequest,
    TokenResponse,
    UserCreate,
    UserLogin,
    UserResponse,
)
from app.services.email_service import EmailService
from app.services.audit_service import record_audit_event

router = APIRouter(prefix="/auth", tags=["Autenticación"])
email_service = EmailService()


def _is_expired(expires_at: datetime, now: datetime) -> bool:
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at < now


@router.post("/register", response_model=TokenResponse, status_code=201)
def register(
    data: UserCreate,
    request: Request,
    db: Session = Depends(get_db),
):
    check_rate_limit(
        request,
        scope="auth-register",
        max_attempts=8,
        window_seconds=60 * 60,
    )
    if not data.accepts_terms:
        raise HTTPException(status_code=400, detail="Debes aceptar los Términos y Condiciones")
    if not data.accepts_privacy:
        raise HTTPException(status_code=400, detail="Debes aceptar la Política de Privacidad")
    if data.role.value == UserRole.driver.value and not data.accepts_driver_documents:
        raise HTTPException(
            status_code=400,
            detail="Debes autorizar la revisión de documentos de conductor",
        )
    if db.query(User).filter(User.email == data.email).first():
        raise HTTPException(status_code=400, detail="El email ya está registrado")
    if db.query(User).filter(User.phone == data.phone).first():
        raise HTTPException(status_code=400, detail="El teléfono ya está registrado")

    user = User(
        email=data.email,
        phone=data.phone,
        full_name=data.full_name,
        hashed_password=hash_password(data.password),
        role=UserRole(data.role.value),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    _record_registration_consents(db, user, data, request)
    user.last_modified_by = user.id
    record_audit_event(
        db,
        actor=user,
        entity_type="user",
        entity_id=user.id,
        event_type="user.registered",
        after_data={"role": user.role.value if hasattr(user.role, "value") else str(user.role)},
        request=request,
    )
    db.commit()

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return TokenResponse(access_token=token, user=UserResponse.model_validate(user))


def _record_registration_consents(
    db: Session,
    user: User,
    data: UserCreate,
    request: Request,
) -> None:
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    consents = [
        UserConsent(
            user_id=user.id,
            consent_type="terms",
            version=settings.TERMS_VERSION,
            ip_address=ip_address,
            user_agent=user_agent,
        ),
        UserConsent(
            user_id=user.id,
            consent_type="privacy",
            version=settings.PRIVACY_VERSION,
            ip_address=ip_address,
            user_agent=user_agent,
        ),
    ]
    if data.role.value == UserRole.driver.value and data.accepts_driver_documents:
        consents.append(
            UserConsent(
                user_id=user.id,
                consent_type="driver_document_verification",
                version=settings.PRIVACY_VERSION,
                ip_address=ip_address,
                user_agent=user_agent,
            )
        )
    db.add_all(consents)
    db.flush()
    for consent in consents:
        record_audit_event(
            db,
            actor=user,
            entity_type="user_consent",
            entity_id=consent.id,
            event_type=f"legal.{consent.consent_type}_accepted",
            after_data={
                "consent_type": consent.consent_type,
                "version": consent.version,
            },
            request=request,
        )
    db.commit()


@router.post("/login", response_model=TokenResponse)
def login(data: UserLogin, request: Request, db: Session = Depends(get_db)):
    check_rate_limit(
        request,
        scope="auth-login",
        identifier=data.email.lower(),
        max_attempts=8,
        window_seconds=15 * 60,
    )
    user = db.query(User).filter(User.email == data.email).first()
    if not user or not verify_password(data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Credenciales incorrectas")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Cuenta suspendida")

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return TokenResponse(access_token=token, user=UserResponse.model_validate(user))


@router.post("/forgot-password", response_model=MessageResponse)
def forgot_password(
    data: PasswordResetRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    check_rate_limit(
        request,
        scope="forgot-password-ip",
        max_attempts=6,
        window_seconds=60 * 60,
    )
    check_rate_limit(
        request,
        scope="forgot-password-email",
        identifier=data.email.lower(),
        max_attempts=3,
        window_seconds=60 * 60,
    )
    generic = "Si el correo existe, enviaremos instrucciones para recuperar la contraseña."
    user = db.query(User).filter(User.email == data.email).first()
    if not user or not user.is_active:
        return MessageResponse(message=generic)

    db.query(PasswordResetToken).filter(
        PasswordResetToken.user_id == user.id,
        PasswordResetToken.used_at.is_(None),
    ).update({"used_at": datetime.now(timezone.utc)})

    raw_token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode("utf-8")).hexdigest()
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.PASSWORD_RESET_EXPIRE_MINUTES
    )
    reset_token = PasswordResetToken(
        user_id=user.id,
        token_hash=token_hash,
        expires_at=expires_at,
    )
    db.add(reset_token)
    db.commit()

    reset_url = f"{settings.FRONTEND_URL.rstrip('/')}/#/reset-password?token={raw_token}"
    try:
        email_service.send_password_reset(user.email, reset_url)
    except Exception as exc:
        print(f"[password-reset] Email send failed for user {user.id}: {exc}")

    return MessageResponse(message=generic)


@router.post("/reset-password", response_model=MessageResponse)
def reset_password(
    data: PasswordResetConfirm,
    request: Request,
    db: Session = Depends(get_db),
):
    check_rate_limit(
        request,
        scope="reset-password",
        max_attempts=10,
        window_seconds=60 * 60,
    )
    token_hash = hashlib.sha256(data.token.encode("utf-8")).hexdigest()
    reset_token = (
        db.query(PasswordResetToken)
        .filter(PasswordResetToken.token_hash == token_hash)
        .first()
    )

    now = datetime.now(timezone.utc)
    if (
        not reset_token
        or reset_token.used_at is not None
        or _is_expired(reset_token.expires_at, now)
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El enlace es inválido o expiró.",
        )

    user = db.query(User).filter(User.id == reset_token.user_id).first()
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El enlace es inválido o expiró.",
        )

    user.hashed_password = hash_password(data.new_password)
    reset_token.used_at = now
    db.commit()

    return MessageResponse(message="Contraseña actualizada correctamente.")
