from datetime import datetime, timedelta, timezone
import hashlib
import secrets

from fastapi import APIRouter, Depends, HTTPException, Request, status
from google.auth import exceptions as google_auth_exceptions
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.rate_limit import check_rate_limit
from app.core.security import (
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.database import get_db
from app.models.password_reset import PasswordResetToken
from app.models.user import User, UserRole
from app.models.user_consent import UserConsent
from app.schemas.user import (
    ActiveRoleUpdate,
    GoogleRegister,
    LegalUpdateAcceptance,
    GoogleLogin,
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
DUMMY_PASSWORD_HASH = hash_password("muvv-invalid-password")
GOOGLE_TOKEN_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


def _legal_reacceptance_required(db: Session, user: User) -> bool:
    current_consents = {
        consent_type
        for (consent_type,) in (
            db.query(UserConsent.consent_type)
            .filter(
                UserConsent.user_id == user.id,
                (
                    ((UserConsent.consent_type == "terms") & (UserConsent.version == settings.TERMS_VERSION))
                    | ((UserConsent.consent_type == "privacy") & (UserConsent.version == settings.PRIVACY_VERSION))
                ),
            )
            .all()
        )
    }
    return not {"terms", "privacy"}.issubset(current_consents)


def _user_response(db: Session, user: User) -> UserResponse:
    return UserResponse.model_validate(user).model_copy(
        update={
            "roles": _account_roles(user),
            "legal_reacceptance_required": _legal_reacceptance_required(db, user),
        }
    )


def _is_expired(expires_at: datetime, now: datetime) -> bool:
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at < now


def _account_roles(user: User) -> list[UserRole]:
    """Return all modes for an identity, including safe legacy fallbacks."""

    raw_roles = getattr(user, "account_roles", None)
    roles: list[UserRole] = []
    if isinstance(raw_roles, list):
        for value in raw_roles:
            try:
                role = UserRole(value)
            except ValueError:
                continue
            if role not in roles:
                roles.append(role)

    if roles:
        return roles
    if user.role == UserRole.driver:
        return [UserRole.client, UserRole.driver]
    return [user.role]


def _requested_account_roles(role: UserRole, also_driver: bool) -> list[str]:
    if role == UserRole.driver or also_driver:
        return [UserRole.client.value, UserRole.driver.value]
    return [UserRole.client.value]


def _requires_driver_consent(role: UserRole, also_driver: bool) -> bool:
    return role == UserRole.driver or also_driver


def _verified_google_identity(id_token_value: str) -> tuple[str, str | None]:
    """Return verified identity data from Google's signed ID token."""

    client_id = settings.GOOGLE_OAUTH_CLIENT_ID.strip()
    if not client_id:
        raise HTTPException(
            status_code=503,
            detail="El acceso con Google aun no esta configurado",
        )

    try:
        claims = google_id_token.verify_oauth2_token(
            id_token_value,
            google_requests.Request(),
            client_id,
        )
    except (ValueError, google_auth_exceptions.GoogleAuthError):
        raise HTTPException(
            status_code=401,
            detail="No se pudo verificar tu cuenta de Google",
        )

    if claims.get("iss") not in GOOGLE_TOKEN_ISSUERS:
        raise HTTPException(status_code=401, detail="No se pudo verificar tu cuenta de Google")
    if claims.get("aud") != client_id:
        raise HTTPException(status_code=401, detail="No se pudo verificar tu cuenta de Google")
    if claims.get("email_verified") is not True:
        raise HTTPException(status_code=401, detail="Tu correo de Google debe estar verificado")

    email = claims.get("email")
    if not isinstance(email, str) or not email.strip():
        raise HTTPException(status_code=401, detail="No se pudo verificar tu cuenta de Google")

    raw_name = claims.get("name")
    name = " ".join(raw_name.split()) if isinstance(raw_name, str) else ""
    return email.strip().lower(), name if 2 <= len(name) <= 120 else None


def _verified_google_email(id_token_value: str) -> str:
    """Return a verified email only after checking Google's signed token."""

    email, _ = _verified_google_identity(id_token_value)
    return email


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
    check_rate_limit(
        request,
        scope="auth-register-email",
        identifier=data.email.lower(),
        max_attempts=3,
        window_seconds=60 * 60,
    )
    if settings.PILOT_MODE and data.email.lower() not in settings.pilot_allowed_emails:
        raise HTTPException(
            status_code=403,
            detail="Este piloto funciona solo con invitacion. Solicita una invitacion al equipo Muvv.",
        )
    if not data.accepts_terms:
        raise HTTPException(status_code=400, detail="Debes aceptar los Términos y Condiciones")
    if not data.accepts_privacy:
        raise HTTPException(status_code=400, detail="Debes aceptar la Política de Privacidad")
    requested_role = UserRole(data.role.value)
    if _requires_driver_consent(requested_role, data.also_driver) and not data.accepts_driver_documents:
        raise HTTPException(
            status_code=400,
            detail="Debes autorizar la revisión de documentos de conductor",
        )
    existing_user = (
        db.query(User)
        .filter((User.email == data.email) | (User.phone == data.phone))
        .first()
    )
    if existing_user:
        raise HTTPException(
            status_code=400,
            detail="No fue posible crear la cuenta. Revisa tus datos o inicia sesion.",
        )

    user = User(
        email=data.email,
        phone=data.phone,
        full_name=data.full_name,
        hashed_password=hash_password(data.password),
        role=requested_role,
        account_roles=_requested_account_roles(requested_role, data.also_driver),
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=400,
            detail="No fue posible crear la cuenta. Revisa tus datos o inicia sesion.",
        )
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
    return TokenResponse(access_token=token, user=_user_response(db, user))


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
    if _requires_driver_consent(UserRole(data.role.value), data.also_driver) and data.accepts_driver_documents:
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
    check_rate_limit(
        request,
        scope="auth-login-ip",
        max_attempts=60,
        window_seconds=15 * 60,
    )
    user = db.query(User).filter(User.email == data.email).first()
    password_is_valid = verify_password(
        data.password,
        user.hashed_password if user else DUMMY_PASSWORD_HASH,
    )
    if not user or not password_is_valid:
        raise HTTPException(status_code=401, detail="Credenciales incorrectas")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Cuenta suspendida")

    now = datetime.now(timezone.utc)
    user.last_login_at = now
    user.last_seen_at = now
    user.last_seen_screen = "/auth/login"
    record_audit_event(
        db,
        actor=user,
        entity_type="user",
        entity_id=user.id,
        event_type="auth.login_succeeded",
        request=request,
        metadata={"source": "password"},
    )
    db.commit()

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return TokenResponse(access_token=token, user=_user_response(db, user))


@router.post("/google/register", response_model=TokenResponse, status_code=201)
def register_with_google(
    data: GoogleRegister,
    request: Request,
    db: Session = Depends(get_db),
):
    """Create an account from a Google identity without collecting a password."""

    check_rate_limit(
        request,
        scope="auth-google-register-ip",
        max_attempts=8,
        window_seconds=60 * 60,
    )
    email, google_name = _verified_google_identity(data.id_token)
    check_rate_limit(
        request,
        scope="auth-google-register-email",
        identifier=email,
        max_attempts=3,
        window_seconds=60 * 60,
    )
    if settings.PILOT_MODE and email not in settings.pilot_allowed_emails:
        raise HTTPException(
            status_code=403,
            detail="Este piloto funciona solo con invitacion. Solicita una invitacion al equipo Muvv.",
        )
    if not data.accepts_terms or not data.accepts_privacy:
        raise HTTPException(status_code=400, detail="Debes aceptar los Terminos y la Politica de Privacidad")

    requested_role = UserRole(data.role.value)
    if _requires_driver_consent(requested_role, data.also_driver) and not data.accepts_driver_documents:
        raise HTTPException(
            status_code=400,
            detail="Debes autorizar la revision de documentos de conductor",
        )
    existing_user = (
        db.query(User)
        .filter((User.email == email) | (User.phone == data.phone))
        .first()
    )
    if existing_user:
        raise HTTPException(
            status_code=400,
            detail="Ya existe una cuenta con estos datos. Inicia sesion con Google o con tu contrasena.",
        )

    full_name = google_name or (data.full_name or "").strip()
    if len(full_name) < 2:
        raise HTTPException(
            status_code=400,
            detail="Tu cuenta de Google no incluye un nombre. Agregalo para continuar.",
        )

    user = User(
        email=email,
        phone=data.phone,
        full_name=full_name,
        # A random non-recoverable credential prevents password login until the
        # person explicitly establishes one through the reset-password flow.
        hashed_password=hash_password(secrets.token_urlsafe(48)),
        role=requested_role,
        account_roles=_requested_account_roles(requested_role, data.also_driver),
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=400,
            detail="No fue posible crear la cuenta. Revisa tus datos o inicia sesion.",
        )
    db.refresh(user)

    _record_registration_consents(db, user, data, request)
    user.last_modified_by = user.id
    record_audit_event(
        db,
        actor=user,
        entity_type="user",
        entity_id=user.id,
        event_type="user.registered",
        after_data={"roles": [role.value for role in _account_roles(user)]},
        request=request,
        metadata={"source": "google"},
    )
    db.commit()

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return TokenResponse(access_token=token, user=_user_response(db, user))


@router.post("/google", response_model=TokenResponse)
def login_with_google(
    data: GoogleLogin,
    request: Request,
    db: Session = Depends(get_db),
):
    """Exchange a verified Google identity for the normal short-lived Muvv JWT."""

    check_rate_limit(
        request,
        scope="auth-google-ip",
        max_attempts=30,
        window_seconds=15 * 60,
    )
    email = _verified_google_email(data.id_token)
    check_rate_limit(
        request,
        scope="auth-google-account",
        identifier=email,
        max_attempts=8,
        window_seconds=15 * 60,
    )

    user = db.query(User).filter(User.email == email).first()
    if not user:
        raise HTTPException(
            status_code=401,
            detail="No encontramos una cuenta Muvv para este correo. Crea tu cuenta primero.",
        )
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Cuenta suspendida")

    now = datetime.now(timezone.utc)
    user.last_login_at = now
    user.last_seen_at = now
    user.last_seen_screen = "/auth/google"
    record_audit_event(
        db,
        actor=user,
        entity_type="user",
        entity_id=user.id,
        event_type="auth.login_succeeded",
        request=request,
        metadata={"source": "google"},
    )
    db.commit()

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return TokenResponse(access_token=token, user=_user_response(db, user))


@router.post("/switch-role", response_model=TokenResponse)
def switch_active_role(
    data: ActiveRoleUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Switch the active app mode without creating another identity."""

    check_rate_limit(
        request,
        scope="auth-switch-role",
        identifier=str(current_user.id),
        max_attempts=20,
        window_seconds=60 * 60,
    )
    requested_role = UserRole(data.role.value)
    if requested_role not in _account_roles(current_user):
        raise HTTPException(status_code=403, detail="Este modo no esta habilitado para tu cuenta")
    if current_user.role != requested_role:
        previous_role = current_user.role
        current_user.role = requested_role
        current_user.last_seen_screen = (
            "/app/driver" if requested_role == UserRole.driver else "/app/client"
        )
        record_audit_event(
            db,
            actor=current_user,
            entity_type="user",
            entity_id=current_user.id,
            event_type="auth.active_role_changed",
            before_data={"role": previous_role.value},
            after_data={"role": requested_role.value},
            request=request,
        )
        db.commit()

    token = create_access_token({"sub": str(current_user.id), "role": current_user.role})
    return TokenResponse(access_token=token, user=_user_response(db, current_user))


@router.post("/accept-legal-update", response_model=UserResponse)
def accept_legal_update(
    data: LegalUpdateAcceptance,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Record an explicit acceptance when terms or privacy policy are revised."""

    if not data.accepts_terms or not data.accepts_privacy:
        raise HTTPException(
            status_code=400,
            detail="Debes aceptar los Terminos y la Politica de Privacidad",
        )

    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    pending = []
    for consent_type, version in (
        ("terms", settings.TERMS_VERSION),
        ("privacy", settings.PRIVACY_VERSION),
    ):
        exists = (
            db.query(UserConsent.id)
            .filter(
                UserConsent.user_id == current_user.id,
                UserConsent.consent_type == consent_type,
                UserConsent.version == version,
            )
            .first()
        )
        if not exists:
            pending.append(
                UserConsent(
                    user_id=current_user.id,
                    consent_type=consent_type,
                    version=version,
                    ip_address=ip_address,
                    user_agent=user_agent,
                )
            )
    if pending:
        db.add_all(pending)
        db.flush()
        for consent in pending:
            record_audit_event(
                db,
                actor=current_user,
                entity_type="user_consent",
                entity_id=consent.id,
                event_type=f"legal.{consent.consent_type}_reaccepted",
                after_data={
                    "consent_type": consent.consent_type,
                    "version": consent.version,
                },
                request=request,
            )
        db.commit()
    return _user_response(db, current_user)


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
    except Exception:
        print("[password-reset] Email delivery failed")

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
    user.last_modified_by = user.id
    record_audit_event(
        db,
        actor=user,
        entity_type="user",
        entity_id=user.id,
        event_type="user.password_reset",
        after_data={"reset_at": now.isoformat()},
        request=request,
    )
    db.commit()

    return MessageResponse(message="Contraseña actualizada correctamente.")
