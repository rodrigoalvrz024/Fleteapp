import os
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("DATABASE_URL", "postgresql://localhost/synthetic")
os.environ.setdefault("SECRET_KEY", "synthetic-mfa-test-key-not-for-production")

from cryptography.fernet import Fernet
from cryptography.hazmat.primitives.hashes import SHA1
from cryptography.hazmat.primitives.twofactor.totp import TOTP
from fastapi import Depends, FastAPI, HTTPException
from fastapi.testclient import TestClient
from fastapi.exceptions import RequestValidationError
from app.core.validation_errors import safe_request_validation_error
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool
from app.core.config import settings
from app.core.security import admin_credential_stamp, authenticate_access_token, create_access_token, get_current_user, require_role
from app.database import Base, get_db
from app.models.admin_second_factor import AdminSecondFactor
from app.models.audit_event import AuditEvent
from app.models.user import User, UserRole
from app.models.user_consent import UserConsent
from app.routers import admin, admin_auth, auth, users
from app.services.admin_mfa_service import matching_counter, open_secret, seal_secret, verify_factor


class AdminMfaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.password = "Synthetic-test-937!"
        cls.password_hash = auth.hash_password(cls.password)

    def setUp(self):
        self.enterContext(patch.object(settings, "ADMIN_MFA_ENCRYPTION_KEY", Fernet.generate_key().decode()))
        self.engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
        self.addCleanup(self.engine.dispose)
        Base.metadata.create_all(self.engine, tables=[Base.metadata.tables[n] for n in
            ("users", "admin_second_factors", "audit_events", "user_consents")])
        self.db = Session(self.engine)
        self.addCleanup(self.db.close)
        self.user = User(id=1, email="admin@example.com", phone="56912345678", full_name="Synthetic Admin",
            hashed_password=self.password_hash, role=UserRole.admin, account_roles=["admin"],
            session_version=0, is_active=True)
        self.secret = b"12345678901234567890"  # Public RFC test key, never production.
        self.factor = AdminSecondFactor(user_id=1, encrypted_secret=seal_secret(1, self.secret),
            last_counter=-1, failures=0, activated_at=datetime.now(timezone.utc))
        self.db.add_all([self.user, self.factor])
        for kind, version in (("terms", settings.ADMIN_TERMS_VERSION), ("privacy", settings.ADMIN_PRIVACY_VERSION)):
            self.db.add(UserConsent(user_id=1, consent_type=kind, version=version))
        self.db.commit()
        self.enterContext(patch.object(admin_auth, "lock_first", side_effect=lambda q: q.first()))
        self.enterContext(patch.object(admin_auth, "check_rate_limit"))
        self.enterContext(patch.object(auth, "check_rate_limit"))
        app = FastAPI()
        app.add_exception_handler(RequestValidationError, safe_request_validation_error)
        app.include_router(admin_auth.router)
        app.include_router(admin.router)
        app.include_router(auth.router)
        app.include_router(users.router)
        app.dependency_overrides[get_db] = lambda: self.db
        @app.get("/private")
        def private(user=Depends(get_current_user)):
            return {"id": user.id}
        @app.get("/admin/probe")
        def probe(user=Depends(require_role("admin"))):
            return {"id": user.id}
        self.client = self.enterContext(TestClient(app, raise_server_exceptions=False))

    def code(self, offset=0):
        return TOTP(self.secret, 6, SHA1(), 30).generate(int(datetime.now(timezone.utc).timestamp()) + offset).decode()

    def login(self, **changes):
        payload = {"email": self.user.email, "password": self.password, "code": self.code()}
        payload.update(changes)
        return self.client.post("/auth/admin/login", json=payload)

    def access(self, token, path="/admin/probe"):
        return self.client.get(path, headers={"Authorization": "Bearer " + token})

    def test_mfa_login_grants_short_session_and_records_no_secrets(self):
        response = self.login()
        self.assertEqual(response.status_code, 200, response.text)
        token = response.json()["access_token"]
        self.assertEqual(self.access(token).status_code, 200)
        from app.core.security import decode_token
        claims = decode_token(token)
        self.assertTrue(claims["admin_mfa"])
        self.assertLessEqual(claims["exp"] - claims["admin_mfa_at"], 1800)
        audit = self.db.query(AuditEvent).one()
        self.assertEqual(audit.event_type, "auth.admin_mfa_login")
        self.assertIsNone(audit.event_metadata)
        self.assertNotIn(self.factor.encrypted_secret, response.text)

    def test_password_only_and_legacy_admin_tokens_are_rejected_everywhere(self):
        normal = create_access_token({"sub": str(self.user.id), "role": self.user.role})
        for path in ("/private", "/admin/probe"):
            self.assertEqual(self.access(normal, path).status_code, 401)
        response = self.client.post("/auth/login", json={"email": self.user.email, "password": self.password})
        self.assertEqual(response.status_code, 403)
        self.assertNotIn("access_token", response.json())

    def test_google_cannot_issue_admin_session(self):
        with patch.object(auth, "_verified_google_email", return_value=self.user.email):
            response = self.client.post("/auth/google", json={"id_token": "synthetic-token-" * 10})
        self.assertEqual(response.status_code, 403, response.text)
        self.assertNotIn("access_token", response.text)

    def test_missing_consent_requires_explicit_current_versions(self):
        self.db.query(UserConsent).delete()
        self.db.commit()
        for changes in ({}, {"accepted_terms_version": "old", "accepted_privacy_version": "old"}):
            self.assertEqual(self.login(**changes).status_code, 403)
            self.assertEqual(self.factor.last_counter, -1)
            self.assertEqual(self.db.query(UserConsent).count(), 0)
        response = self.login(accepted_terms_version=settings.ADMIN_TERMS_VERSION,
                              accepted_privacy_version=settings.ADMIN_PRIVACY_VERSION)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertFalse(response.json()["user"]["legal_reacceptance_required"])
        self.assertEqual(self.db.query(UserConsent).count(), 2)
        self.assertEqual(self.access(response.json()["access_token"]).status_code, 200)
        profile = self.access(response.json()["access_token"], "/users/me")
        self.assertEqual(profile.status_code, 200, profile.text)
        self.assertFalse(profile.json()["legal_reacceptance_required"])

    def test_mobile_consent_versions_remain_unchanged(self):
        from app.services.legal_versions import consent_versions
        for role in (UserRole.client, UserRole.driver):
            self.assertEqual(consent_versions(role), (settings.TERMS_VERSION, settings.PRIVACY_VERSION))

    def test_client_and_driver_keep_normal_access_but_cannot_get_admin_token(self):
        for role in (UserRole.client, UserRole.driver):
            self.user.role = role
            self.db.commit()
            token = create_access_token({"sub": str(self.user.id), "role": self.user.role})
            self.assertEqual(self.access(token, "/private").status_code, 200)
            self.assertEqual(self.access(token).status_code, 403)
            self.assertEqual(self.login().status_code, 401)

    def test_used_code_cannot_be_replayed(self):
        code = self.code()
        self.assertEqual(self.login(code=code).status_code, 200)
        self.assertEqual(self.login(code=code).status_code, 401)

    def test_otp_failures_lock_persistently(self):
        for _ in range(5):
            with self.assertRaises(HTTPException):
                verify_factor(self.db, self.factor, "invalid", datetime.now(timezone.utc))
        self.db.expire_all()
        self.assertEqual(self.db.get(AdminSecondFactor, 1).failures, 5)
        self.assertEqual(self.login().status_code, 429)

    def test_expired_lock_allows_correct_new_code(self):
        self.factor.failures = 5
        self.factor.locked_until = datetime.now(timezone.utc) - timedelta(seconds=1)
        self.db.commit()
        self.assertEqual(self.login().status_code, 200)
        self.assertEqual(self.factor.failures, 0)

    def test_wrong_password_does_not_consume_code(self):
        self.assertEqual(self.login(password="wrong").status_code, 401)
        self.assertEqual(self.factor.last_counter, -1)
        self.assertEqual(self.login().status_code, 200)

    def test_missing_factor_cannot_login(self):
        self.db.delete(self.factor)
        self.db.commit()
        self.assertEqual(self.login().status_code, 401)

    def test_deleted_or_suspended_admin_cannot_login(self):
        self.user.is_active = False
        self.db.commit()
        self.assertEqual(self.login().status_code, 401)
        self.user.is_active = True
        self.user.deleted_at = datetime.now(timezone.utc)
        self.db.commit()
        self.assertEqual(self.login().status_code, 401)

    def test_missing_or_wrong_encryption_key_fails_closed(self):
        for key in ("", Fernet.generate_key().decode()):
            with patch.object(settings, "ADMIN_MFA_ENCRYPTION_KEY", key):
                self.assertEqual(self.login().status_code, 503)

    def test_ciphertext_bound_to_owner(self):
        self.factor.encrypted_secret = seal_secret(2, self.secret)
        self.db.commit()
        self.assertEqual(self.login().status_code, 503)

    def test_audit_failure_rolls_back_consumption_and_token(self):
        with patch.object(admin_auth, "record_audit_event", side_effect=RuntimeError("PRIVATE")):
            response = self.login()
        self.assertEqual(response.status_code, 500)
        self.assertNotIn("PRIVATE", response.text)
        self.assertEqual(self.factor.last_counter, -1)
        self.assertEqual(self.login().status_code, 200)

    def test_logout_revokes_token_on_server(self):
        token = self.login().json()["access_token"]
        response = self.client.post("/auth/admin/logout", headers={"Authorization": "Bearer " + token})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.access(token).status_code, 401)

    def test_password_change_revokes_existing_admin_session(self):
        token = self.login().json()["access_token"]
        self.user.hashed_password = auth.hash_password("Another-synthetic-password-84!")
        self.db.commit()
        self.assertEqual(self.access(token).status_code, 401)

    def test_suspend_and_reactivate_cannot_resurrect_admin_session(self):
        from admin_test_tokens import authenticated_admin_token
        operator = User(id=2, email="operator@example.com", phone="56987654321", full_name="Operator",
            hashed_password=self.password_hash, role=UserRole.admin, account_roles=["admin"], is_active=True)
        self.db.add(operator)
        self.db.commit()
        headers = {"Authorization": "Bearer " + authenticated_admin_token(self.db, operator)}
        token = self.login().json()["access_token"]
        for action in ("suspend", "activate"):
            response = self.client.put(f"/admin/users/1/{action}", headers=headers)
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(self.access(token).status_code, 401)
        self.assertTrue(self.user.is_active)
        self.assertEqual(self.user.session_version, 2)

    def test_factor_removal_revokes_existing_admin_session(self):
        token = self.login().json()["access_token"]
        self.db.delete(self.factor)
        self.db.commit()
        self.assertEqual(self.access(token).status_code, 401)

    def test_admin_cannot_switch_to_mobile_mode(self):
        self.user.account_roles = ["admin", "client", "driver"]
        self.db.commit()
        token = self.login().json()["access_token"]
        response = self.client.post("/auth/switch-role", json={"role": "client"},
            headers={"Authorization": "Bearer " + token})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.user.role, UserRole.admin)

    def test_analytics_rejects_old_and_revoked_admin_tokens(self):
        from fastapi.security import HTTPAuthorizationCredentials
        from app.routers.analytics import _optional_current_user
        token = create_access_token({"sub": "1", "role": "admin"})
        credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)
        self.assertIsNone(_optional_current_user(credentials, self.db))
        token = self.login().json()["access_token"]
        credentials.credentials = token
        self.assertEqual(_optional_current_user(credentials, self.db).id, 1)
        self.user.session_version += 1
        self.db.commit()
        self.assertIsNone(_optional_current_user(credentials, self.db))

    def test_websocket_auth_blocks_admin_and_keeps_mobile_users(self):
        import asyncio
        from unittest.mock import AsyncMock, MagicMock
        from app.routers import chat
        for role in (UserRole.admin, UserRole.client, UserRole.driver):
            self.user.role = role
            self.db.commit()
            token = (self.login().json()["access_token"] if role == UserRole.admin
                else create_access_token({"sub": "1", "role": role}))
            socket = AsyncMock()
            socket.receive_json.return_value = {"type": "auth", "token": token}
            db_proxy = MagicMock(wraps=self.db)
            db_proxy.close = MagicMock()
            with patch.object(chat, "SessionLocal", return_value=db_proxy):
                result = asyncio.run(chat._websocket_user(socket))
            if role == UserRole.admin:
                self.assertIsNone(result)
            else:
                self.assertEqual(result.id, 1)

    def test_invalid_payload_does_not_reflect_credentials(self):
        response = self.login(code="PRIVATE-OTP-VALUE", password="P" * 100)
        self.assertEqual(response.status_code, 422)
        self.assertNotIn("PRIVATE-OTP-VALUE", response.text)
        self.assertNotIn("P" * 100, response.text)

    def test_mfa_age_type_and_lifetime_are_checked(self):
        now = int(datetime.now(timezone.utc).timestamp())
        for changes in ({"admin_mfa": False}, {"admin_mfa_at": True}, {"admin_mfa_at": now-1801},
                        {"admin_mfa_at": now+10}):
            claims = {"sub": "1", "session_version": 0, "admin_mfa": True, "admin_mfa_at": now, "admin_credentials": admin_credential_stamp(self.user)}
            claims.update(changes)
            token = create_access_token(claims, expires_delta=timedelta(minutes=5))
            self.assertEqual(self.access(token).status_code, 401)
        token = create_access_token({"sub": "1", "session_version": 0,
            "admin_mfa": True, "admin_mfa_at": now}, expires_delta=timedelta(hours=1))
        self.assertEqual(self.access(token).status_code, 401)

    def test_malformed_codes_never_reach_verifier(self):
        for code in ("", "12345", "1234567", "abcdef", "１２３４５６"):
            self.assertEqual(self.login(code=code).status_code, 422)

    def test_factor_matches_rfc_counter_and_only_small_time_window(self):
        now = datetime.fromtimestamp(59, timezone.utc)
        self.assertEqual(matching_counter(self.secret, "287082", now), 1)
        self.assertIsNone(matching_counter(self.secret, "287082", now + timedelta(seconds=120)))
        self.assertNotEqual(self.factor.encrypted_secret, self.secret.decode())
        self.assertEqual(open_secret(self.factor), self.secret)
