"""TOTP verification with encrypted secrets and durable, serialized replay protection."""
import json
from datetime import datetime, timedelta, timezone

from cryptography.fernet import Fernet, InvalidToken as InvalidCiphertext
from cryptography.hazmat.primitives.hashes import SHA1
from cryptography.hazmat.primitives.twofactor import InvalidToken as InvalidOTP
from cryptography.hazmat.primitives.twofactor.totp import TOTP
from fastapi import HTTPException

from app.core.config import settings


def cipher():
    try:
        return Fernet(settings.ADMIN_MFA_ENCRYPTION_KEY.encode("ascii"))
    except (ValueError, UnicodeError):
        raise HTTPException(503, "Acceso administrativo no disponible") from None


def seal_secret(user_id: int, secret: bytes) -> str:
    # Bind ciphertext to its owner, so copying a database row cannot change factors.
    payload = json.dumps({"user_id": user_id, "secret": secret.hex()}).encode()
    return cipher().encrypt(payload).decode("ascii")


def open_secret(factor) -> bytes:
    try:
        payload = json.loads(cipher().decrypt(factor.encrypted_secret.encode("ascii")))
        secret = bytes.fromhex(payload["secret"])
        if payload["user_id"] != factor.user_id or len(secret) != 20:
            raise ValueError
        return secret
    except (InvalidCiphertext, ValueError, KeyError, TypeError, UnicodeError):
        raise HTTPException(503, "Acceso administrativo no disponible") from None


def matching_counter(secret: bytes, code: str, now: datetime) -> int | None:
    if len(code) != 6 or not code.isascii() or not code.isdigit():
        return None
    totp = TOTP(secret, 6, SHA1(), 30)
    current = int(now.timestamp()) // 30
    # Only current/adjacent 30-second windows, never an unbounded time search.
    matches = []
    for counter in (current - 1, current, current + 1):
        try:
            totp.verify(code.encode("ascii"), counter * 30)
            matches.append(counter)
        except InvalidOTP:
            pass
    return max(matches) if matches else None


def verify_factor(db, factor, code: str, now: datetime) -> None:
    """Caller holds the user and factor row locks until its final commit."""
    if factor is None:
        raise HTTPException(401, "No se pudo verificar el acceso administrativo")
    until = factor.locked_until
    if until is not None:
        if until.tzinfo is None:
            until = until.replace(tzinfo=timezone.utc)
        if until > now:
            raise HTTPException(429, "Demasiados intentos. Intenta mas tarde.",
                                headers={"Retry-After": str(max(1, int((until - now).total_seconds())))})
        factor.failures = 0
        factor.locked_until = None
    counter = matching_counter(open_secret(factor), code, now)
    if counter is None or counter <= factor.last_counter:
        factor.failures += 1
        if factor.failures >= 5:
            factor.locked_until = now + timedelta(minutes=15)
        db.commit()  # Failed attempts survive retries, restarts and other workers.
        raise HTTPException(401, "No se pudo verificar el acceso administrativo")
    factor.last_counter = counter
    factor.failures = 0
    factor.locked_until = None
