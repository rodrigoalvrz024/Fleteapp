from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from app.core.config import settings
from app.database import get_db


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer_scheme = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return pwd_context.verify(plain, hashed)
    except (ValueError, TypeError):
        return False


def create_access_token(
    data: dict,
    expires_delta: Optional[timedelta] = None,
) -> str:
    payload = data.copy()
    now = datetime.now(timezone.utc)
    role = payload.get("role")
    if hasattr(role, "value"):
        payload["role"] = role.value
    payload.update(
        {
            "exp": now + (
                expires_delta
                or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
            ),
            "iat": now,
            "iss": settings.JWT_ISSUER,
            "aud": settings.JWT_AUDIENCE,
            "token_type": "access",
        }
    )
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def _invalid_token() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token invalido o expirado",
        headers={"WWW-Authenticate": "Bearer"},
    )


def decode_token(token: str) -> dict:
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
            issuer=settings.JWT_ISSUER,
            audience=settings.JWT_AUDIENCE,
        )
    except JWTError:
        raise _invalid_token()
    if payload.get("token_type") != "access":
        raise _invalid_token()
    return payload


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
):
    from app.models.user import User

    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Autenticacion requerida",
            headers={"WWW-Authenticate": "Bearer"},
        )
    payload = decode_token(credentials.credentials)
    try:
        user_id = int(payload.get("sub"))
    except (TypeError, ValueError):
        raise _invalid_token()

    user = db.query(User).filter(User.id == user_id).first()
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sesion no disponible",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def require_role(*roles: str):
    def checker(current_user=Depends(get_current_user)):
        if current_user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tienes permiso para esta accion",
            )
        return current_user

    return checker
