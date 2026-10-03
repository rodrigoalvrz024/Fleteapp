"""Operator-only interactive enrollment. Never run with logged/redirected output."""
import argparse
import base64
import getpass
import secrets
import sys
from datetime import datetime, timezone

from app.database import SessionLocal
from app.models.admin_second_factor import AdminSecondFactor
from app.models.user import User, UserRole
from app.services.admin_mfa_service import cipher, matching_counter, seal_secret
from app.services.audit_service import record_audit_event
from app.services.row_lock_service import lock_first


def main():
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise SystemExit("Solo consola interactiva privada; no redirigir ni registrar la salida.")
    parser = argparse.ArgumentParser(description="Vincular autenticador de un administrador existente")
    parser.add_argument("email")
    parser.add_argument("--reset", action="store_true")
    args = parser.parse_args()
    cipher()  # Check the independent encryption key before exposing a new secret.
    with SessionLocal() as db:
        user = db.query(User).filter(User.email == args.email.strip().lower()).first()
        if not user or user.role != UserRole.admin or not user.is_active or user.deleted_at:
            raise SystemExit("Administrador activo no encontrado.")
        user_id, version, password_hash = user.id, user.session_version, user.hashed_password
        existing = db.get(AdminSecondFactor, user_id)
        if existing and not args.reset:
            raise SystemExit("Ya tiene autenticador. Recuperacion requiere --reset y verificacion de identidad.")
        db.rollback()  # Do not hold database locks while the operator uses their phone.
        if args.reset and input("Tras verificar identidad fuera de la app, escribe RESTABLECER: ") != "RESTABLECER":
            raise SystemExit("Cancelado; sin cambios.")
        secret = secrets.token_bytes(20)
        print("En tu autenticador agrega Muvv Admin, clave basada en tiempo (30 segundos, 6 digitos).")
        print("Clave privada (no compartir ni fotografiar):", base64.b32encode(secret).decode())
        code = getpass.getpass("Codigo de tu autenticador: ")
        now = datetime.now(timezone.utc)
        counter = matching_counter(secret, code, now)
        if counter is None:
            raise SystemExit("Codigo incorrecto; no se guardo nada. Elimina la entrada de prueba del autenticador.")
        user = lock_first(db.query(User).filter(User.id == user_id).populate_existing())
        if (not user or user.role != UserRole.admin or not user.is_active or user.deleted_at
                or user.session_version != version or user.hashed_password != password_hash):
            raise SystemExit("La cuenta cambio durante la vinculacion; no se guardo nada.")
        factor = lock_first(db.query(AdminSecondFactor).filter(
            AdminSecondFactor.user_id == user_id).populate_existing())
        if factor and not args.reset:
            raise SystemExit("La cuenta ya fue vinculada por otro operador; sin cambios.")
        if factor is None:
            factor = AdminSecondFactor(user_id=user_id)
            db.add(factor)
        factor.encrypted_secret = seal_secret(user_id, secret)
        factor.last_counter = counter
        factor.failures = 0
        factor.locked_until = None
        factor.activated_at = now
        user.session_version += 1
        record_audit_event(db, actor=user, entity_type="user", entity_id=user_id,
                          event_type="auth.admin_mfa_reset" if args.reset else "auth.admin_mfa_enrolled")
        db.commit()
        print("Autenticador confirmado. Sesiones anteriores revocadas. Espera el siguiente codigo para ingresar.")


if __name__ == "__main__":
    main()
