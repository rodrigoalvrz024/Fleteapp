"""Run only via test-supabase-rls-isolated.py --http, never against an existing DB."""

import asyncio
import importlib.util
import hashlib
import gc
import http.client
import json
import os
from pathlib import Path
import re
import sys
import socket
import threading
import time
import unittest
import warnings
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from urllib.parse import urlsplit

from alembic import command
from alembic.config import Config
from fastapi.responses import Response
from fastapi import HTTPException
from fastapi.testclient import TestClient
import jwt
import httpx
import psycopg2
from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.orm import Session as OrmSession, sessionmaker
from sqlalchemy.engine import Engine, make_url
from starlette.websockets import WebSocketDisconnect
import uvicorn
from websockets.sync.client import connect as websocket_connect
from websockets.exceptions import ConnectionClosed
from app.server import websocket_options


URL = make_url(os.environ.get("DATABASE_URL", "sqlite://"))
if not (
    os.environ.get("MUVV_ISOLATED_HTTP_TEST") == "1"
    and os.environ.get("APP_ENV") == "test"
    and URL.host == "127.0.0.1"
    and URL.username == "muvv_http_owner"
    and re.fullmatch(r"muvv_http_[0-9a-f]{16}", URL.database or "")
    and URL.database == os.environ.get("MUVV_HTTP_DATABASE")
    and not Path(".env").exists()
):
    raise RuntimeError("Use the disposable PostgreSQL runner; existing databases are forbidden.")

NETWORK_ATTEMPTS = []


def guard_network(event, args):
    if event == "socket.connect" and isinstance(args[1], tuple):
        if args[1][0] not in {"127.0.0.1", "::1"}:
            NETWORK_ATTEMPTS.append(event)
            raise RuntimeError("External network access forbidden in this test suite.")


sys.addaudithook(guard_network)

from app.core.config import settings
from app.core.rate_limit import _BUCKETS
from app.core.security import create_access_token, hash_password
from app.database import Base, SessionLocal, engine
from app import database
from app.main import app
from app.models.audit_event import AuditEvent
from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest, FreightStatus, FreightCargoPhoto, TripFeedback, TripStatusHistory
from app.models.freight_chat import FreightChatMessage
from app.models.payment import Payment, PaymentMethod, PaymentStatus
from app.models.password_reset import PasswordResetToken
from app.models.user import User, UserRole
from app.models.vehicle import Vehicle, VehicleType
from app.routers import auth, chat, feedback, freights
from app.services import transbank_service


ROOT = Path(__file__).resolve().parents[1]
REAL_HTTPX_CLIENT = httpx.Client
TLS_CONNECTIONS = []


def verify_fixture_tls(dbapi_connection, connection_record=None):
    if URL.query.get("sslmode") != "verify-full":
        return
    parameters = dbapi_connection.get_dsn_parameters()
    if (not dbapi_connection.info.ssl_in_use
            or dbapi_connection.info.ssl_attribute("protocol") not in {"TLSv1.2", "TLSv1.3"}
            or parameters.get("sslmode") != "verify-full"
            or parameters.get("sslrootcert") != URL.query["sslrootcert"]):
        raise RuntimeError("Expected verified TLS for every HTTP test database connection")
    TLS_CONNECTIONS.append(True)


# Check pooled API, migration and auxiliary SQLAlchemy connections before SQL.
event.listen(Engine, "connect", verify_fixture_tls)


def raw_connection_options():
    options = dict(host=URL.host, port=URL.port, dbname=URL.database,
                   user=URL.username, password=URL.password, connect_timeout=5)
    for name in ("sslmode", "sslrootcert"):
        if name in URL.query:
            options[name] = URL.query[name]
    return options


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HttpPermissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.addClassCleanup(engine.dispose)
        for field in ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "FIREBASE_CREDENTIALS_JSON",
                      "GOOGLE_MAPS_KEY", "GOOGLE_OAUTH_CLIENT_ID", "RESEND_API_KEY",
                      "TRANSBANK_API_KEY", "TRANSBANK_COMMERCE_CODE", "CLOUD_TASKS_TARGET_BASE_URL"):
            if getattr(settings, field):
                raise RuntimeError("External integration credentials must be absent.")
        if settings.RUN_STARTUP_MIGRATIONS or app.dependency_overrides:
            raise RuntimeError("Startup migrations and authentication overrides must be disabled.")
        with engine.begin() as conn:
            identity = conn.execute(text(
                "SELECT current_database(), current_user, rolsuper, rolbypassrls "
                "FROM pg_roles WHERE rolname=current_user"
            )).one()
            if tuple(identity) != (URL.database, "muvv_http_owner", False, False):
                raise RuntimeError("Unexpected database or privileged application role.")
            if inspect(conn).get_table_names(schema="public"):
                raise RuntimeError("Refusing to overwrite an existing schema.")
            conn.exec_driver_sql("GRANT USAGE ON SCHEMA public TO anon, authenticated")
        config = Config(str(ROOT / "alembic.ini"))
        config.set_main_option("script_location", str(ROOT / "alembic"))
        command.upgrade(config, "head")
        cls.password = "Synthetic-local-test-Only-935!"
        cls.password_hash = hash_password(cls.password)

    def setUp(self):
        self.expected_backend_errors = 0
        self.resource_warnings = self.enterContext(warnings.catch_warnings(record=True))
        warnings.simplefilter("always", ResourceWarning)
        # Registered before clients, so this runs after their LIFO cleanup.
        self.addCleanup(self.assert_streams_closed)
        _BUCKETS.clear()
        with engine.begin() as conn:
            quote = conn.dialect.identifier_preparer.quote
            names = ", ".join(quote(name) for name in Base.metadata.tables)
            conn.exec_driver_sql(f"TRUNCATE {names} RESTART IDENTITY CASCADE")
        self.seed()
        self.push = self.enterContext(patch.object(chat, "_notify_chat_recipient", new_callable=AsyncMock))
        self.transport = self.enterContext(patch("httpx.HTTPTransport.handle_request", side_effect=AssertionError("Outbound HTTP forbidden")))
        self.async_transport = self.enterContext(patch("httpx.AsyncHTTPTransport.handle_async_request", side_effect=AssertionError("Outbound HTTP forbidden")))
        self.http = self.enterContext(TestClient(app, raise_server_exceptions=True))

    def assert_streams_closed(self):
        gc.collect()
        resources = [item for item in self.resource_warnings if issubclass(item.category, ResourceWarning)]
        self.assertEqual(len(resources), 0, "Unclosed resource detected after HTTP/WebSocket cleanup")

    def tearDown(self):
        self.transport.assert_not_called()
        self.async_transport.assert_not_called()
        self.assertEqual(NETWORK_ATTEMPTS, [])
        with SessionLocal() as db:
            self.assertEqual(db.query(AuditEvent).filter(AuditEvent.event_type == "system.backend_error").count(),
                             self.expected_backend_errors)

    def seed(self):
        future = datetime.now(timezone.utc) + timedelta(days=60)
        with SessionLocal() as db:
            for user_id, role in ((1, "client"), (2, "client"), (3, "driver"), (4, "driver"),
                                  (5, "admin"), (6, "driver"), (7, "client"), (8, "driver"), (9, "driver")):
                db.add(User(id=user_id, email=f"fixture{user_id}@example.com", phone=f"+5690000000{user_id}",
                            full_name=f"Synthetic User {user_id}", role=UserRole(role), account_roles=[role],
                            hashed_password=self.password_hash, is_active=user_id != 7))
            db.flush()
            for user_id, vehicle_type in ((3, "van"), (4, "van"), (6, "van"), (8, "pickup"), (9, "truck_medium")):
                driver_id = user_id * 10
                driver = Driver(id=driver_id, user_id=user_id, rut=f"synthetic-{user_id}", license_number="TEST",
                                license_expiry=future, license_image_url=f"drivers/{driver_id}/license.jpg",
                                circulation_permit_url=f"drivers/{driver_id}/permit.jpg", circulation_permit_expiry=future,
                                technical_review_url=f"drivers/{driver_id}/review.jpg", technical_review_expiry=future,
                                soap_url=f"drivers/{driver_id}/soap.jpg", soap_expiry=future,
                                status=DriverStatus.pending if user_id == 6 else DriverStatus.approved)
                driver.vehicles.append(Vehicle(id=driver_id, type=VehicleType(vehicle_type), brand="Synthetic",
                                               model="Fixture", year=2024, plate=f"TEST{user_id}", color="White",
                                               max_weight_kg=5000, max_volume_m3=30, approval_status="approved"))
                db.add(driver)
            db.flush()
            for fid, client_id, driver_id, status in (
                (101, 1, 30, "accepted"), (102, 2, 40, "accepted"), (103, 1, None, "pending"),
                (104, 1, None, "pending"), (105, 1, None, "pending"), (106, 1, 30, "completed"),
            ):
                moving = fid == 105
                freight = FreightRequest(
                    id=fid, client_id=client_id, driver_id=driver_id, status=FreightStatus(status),
                    origin_address="Synthetic origin", origin_lat=-33.45, origin_lng=-70.66,
                    destination_address="Synthetic destination", destination_lat=-33.44, destination_lng=-70.65,
                    cargo_description="Synthetic cargo", cargo_weight_kg=100, cargo_volume_m3=1,
                    service_type="moving" if moving else "package", selected_vehicle_type="truck_medium" if moving else "van",
                    distance_km=5, estimated_price=50000 if moving else 12000,
                    client_pays=50000 if moving else 12000, driver_receives=10000, platform_fee=2000,
                    scheduled_at=datetime.now(timezone.utc) + timedelta(minutes=10),
                )
                db.add(freight)
                db.flush()
                db.add(Payment(freight_id=fid, amount=freight.client_pays, method=PaymentMethod.transfer,
                               status=PaymentStatus.pending if fid == 104 else PaymentStatus.authorized))
            db.add_all([
                FreightCargoPhoto(id=301, freight_id=101, client_id=1, object_ref="freights/101/cargo/test.jpg", content_type="image/jpeg", size_bytes=4),
                FreightCargoPhoto(id=303, freight_id=103, client_id=1, object_ref="freights/103/cargo/test.jpg", content_type="image/jpeg", size_bytes=4),
                FreightChatMessage(id=201, freight_id=101, sender_user_id=1, receiver_user_id=3, message_text="Synthetic private message"),
                FreightChatMessage(id=202, freight_id=102, sender_user_id=2, receiver_user_id=4, message_text="Other synthetic conversation"),
            ])
            db.commit()

    def request(self, method, path, user=None, token=None, **kwargs):
        if user is not None:
            token = token or create_access_token({"sub": str(user), "role": "client"})
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        return self.http.request(method, path, headers=headers, **kwargs)

    def assert_status(self, response, expected):
        # Do not include bearer URLs, tokens or response bodies in failure logs.
        self.assertEqual(response.status_code, expected)

    @unittest.skipUnless(URL.query.get("sslmode") == "verify-full", "Run with --tls")
    def test_http_request_opens_a_verified_tls_connection(self):
        engine.dispose()
        before = len(TLS_CONNECTIONS)
        self.assert_status(self.request("GET", "/users/me", user=1), 200)
        self.assertGreater(len(TLS_CONNECTIONS), before)

    @unittest.skipUnless(URL.query.get("sslmode") == "verify-full", "Run with --tls")
    def test_tls_observer_rejects_encryption_without_hostname_verification(self):
        options = raw_connection_options()
        options["sslmode"] = "require"
        raw = psycopg2.connect(**options)
        try:
            self.assertTrue(raw.info.ssl_in_use)
            before = len(TLS_CONNECTIONS)
            with self.assertRaisesRegex(RuntimeError, "Expected verified TLS"):
                verify_fixture_tls(raw)
            self.assertEqual(len(TLS_CONNECTIONS), before)
        finally:
            raw.close()

    def test_full_schema_rls_and_unprivileged_owner(self):
        with engine.connect() as conn:
            rows = conn.execute(text("SELECT relname, relrowsecurity FROM pg_class WHERE relnamespace='public'::regnamespace AND relkind='r' AND relname <> 'alembic_version'")).all()
            self.assertEqual({row[0] for row in rows}, set(Base.metadata.tables))
            self.assertTrue(all(row[1] for row in rows))
            self.assertEqual(len(rows), 20)
        verifier = load_module("http_access_verifier", ROOT.parent / "scripts/verify-supabase-rls.py")
        # The verifier changes psycopg session defaults; never return that connection to the app pool.
        raw = psycopg2.connect(**raw_connection_options())
        try:
            verify_fixture_tls(raw)
            verifier.begin_read_only_inspection(raw)
            result = verifier.inspect_access(raw)
            self.assertEqual(result["checked"], 20)
            self.assertEqual(result["grants"], [])
            self.assertEqual(result["column_grants"], [])
        finally:
            raw.rollback()
            raw.close()

    def test_missing_invalid_expired_and_wrong_audience_tokens_are_denied(self):
        expired = create_access_token({"sub": "1"}, expires_delta=timedelta(seconds=-10))
        claims = jwt.decode(create_access_token({"sub": "1"}), options={"verify_signature": False})
        claims["aud"] = "not-muvv"
        wrong_audience = jwt.encode(claims, settings.SECRET_KEY, algorithm="HS256")
        for token in (None, "invalid-token", expired, wrong_audience):
            with self.subTest(kind="invalid credential"):
                self.assert_status(self.request("GET", "/freights/101", token=token), 401)

    def test_suspended_user_is_denied_with_valid_token(self):
        self.assert_status(self.request("GET", "/users/me", user=7), 401)

    def test_password_login_and_failed_login_limit(self):
        valid = self.http.post("/auth/login", json={"email": "fixture1@example.com", "password": self.password})
        self.assert_status(valid, 200)
        self.assert_status(self.request("GET", "/users/me", token=valid.json()["access_token"]), 200)
        for _ in range(8):
            self.assert_status(self.http.post("/auth/login", json={"email": "fixture2@example.com", "password": "incorrect"}), 401)
        self.assert_status(self.http.post("/auth/login", json={"email": "fixture2@example.com", "password": "incorrect"}), 429)

    def test_claimed_admin_role_does_not_override_database_role(self):
        token = create_access_token({"sub": "1", "role": "admin"})
        self.assert_status(self.request("GET", "/admin/users", token=token), 403)

    def reset_fixture_password(self, user_id):
        raw = f"synthetic-reset-token-for-user-{user_id}-not-a-secret"
        with SessionLocal() as db:
            db.add(PasswordResetToken(user_id=user_id,
                token_hash=hashlib.sha256(raw.encode()).hexdigest(),
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=5)))
            db.commit()
        return self.http.post("/auth/reset-password", json={
            "token": raw, "new_password": "New-synthetic-password-935!"})

    def test_password_recovery_revokes_previous_sessions_for_every_role(self):
        for user_id in (1, 3, 5):
            with self.subTest(role_user=user_id):
                old = create_access_token({"sub": str(user_id)})
                self.assert_status(self.reset_fixture_password(user_id), 200)
                self.assert_status(self.request("GET", "/users/me", token=old), 401)
                login = self.http.post("/auth/login", json={
                    "email": f"fixture{user_id}@example.com", "password": "New-synthetic-password-935!"})
                self.assert_status(login, 200)
                new = login.json()["access_token"]
                self.assert_status(self.request("GET", "/users/me", token=new), 200)
                self.assert_status(self.request("GET", "/admin/users", token=new), 200 if user_id == 5 else 403)
        self.assert_status(self.request("GET", "/users/me", user=2), 200)

    def test_open_chat_rejects_suspended_account_before_pong(self):
        with self.http.websocket_connect("/freights/101/chat/live") as ws:
            ws.send_json({"type": "auth", "token": create_access_token({"sub": "1"})})
            self.assertEqual(ws.receive_json()["type"], "ready")
            with SessionLocal() as db:
                db.get(User, 1).is_active = False
                db.commit()
            ws.send_json({"type": "ping"})
            with self.assertRaises(WebSocketDisconnect) as error:
                ws.receive_json()
            self.assertEqual(error.exception.code, 4401)

    def test_open_chat_rechecks_participation_before_broadcast(self):
        with self.http.websocket_connect("/freights/101/chat/live") as ws:
            ws.send_json({"type": "auth", "token": create_access_token({"sub": "3"})})
            self.assertEqual(ws.receive_json()["type"], "ready")
            with SessionLocal() as db:
                db.get(FreightRequest, 101).driver_id = 40
                db.commit()
            self.assert_status(self.request("POST", "/freights/101/chat/messages", user=1,
                json={"message_text": "Only the newly assigned driver may receive this"}), 201)
            with self.assertRaises(WebSocketDisconnect) as error:
                ws.receive_json()
            self.assertEqual(error.exception.code, 4403)

    def test_password_recovery_blocks_chat_broadcast_and_analytics(self):
        old = create_access_token({"sub": "1"})
        with self.http.websocket_connect("/freights/101/chat/live") as ws:
            ws.send_json({"type": "auth", "token": old})
            self.assertEqual(ws.receive_json()["type"], "ready")
            self.assert_status(self.reset_fixture_password(1), 200)
            self.assert_status(self.request("POST", "/analytics/presence", token=old,
                json={"screen": "/app/client"}), 401)
            self.assert_status(self.request("POST", "/analytics/events", token=old,
                json={"event_type": "app.screen_view", "entity_type": "screen", "entity_id": "/app/client"}), 401)
            self.assert_status(self.request("POST", "/freights/101/chat/messages", user=3,
                json={"message_text": "Revoked session must not receive this"}), 201)
            with self.assertRaises(WebSocketDisconnect) as error:
                ws.receive_json()
            self.assertEqual(error.exception.code, 4401)
        with self.http.websocket_connect("/freights/101/chat/live") as ws:
            ws.send_json({"type": "auth", "token": old})
            with self.assertRaises(WebSocketDisconnect) as error:
                ws.receive_json()
            self.assertEqual(error.exception.code, 4401)

    def test_idle_chat_closes_after_token_expires(self):
        with patch.object(chat, "CHAT_SESSION_RECHECK_SECONDS", 0.05):
            with self.http.websocket_connect("/freights/101/chat/live") as ws:
                ws.send_json({"type": "auth", "token": create_access_token(
                    {"sub": "1"}, expires_delta=timedelta(seconds=2))})
                self.assertEqual(ws.receive_json()["type"], "ready")
                with self.assertRaises(WebSocketDisconnect) as error:
                    ws.receive_json()
                self.assertEqual(error.exception.code, 4401)

    def test_chat_event_limit_precedes_database_revalidation(self):
        with self.http.websocket_connect("/freights/101/chat/live") as ws:
            ws.send_json({"type": "auth", "token": create_access_token({"sub": "1"})})
            self.assertEqual(ws.receive_json()["type"], "ready")
            with patch.object(chat, "check_rate_limit", side_effect=HTTPException(status_code=429)), \
                 patch.object(chat, "_live_chat_access", side_effect=AssertionError("Must limit before DB access")) as query:
                ws.send_json({"type": "ping"})
                with self.assertRaises(WebSocketDisconnect) as error:
                    ws.receive_json()
                self.assertEqual(error.exception.code, 4429)
                query.assert_not_called()

    def test_concurrent_password_reset_is_single_use(self):
        raw = "synthetic-concurrent-reset-not-a-secret"
        with SessionLocal() as db:
            db.add(PasswordResetToken(user_id=1, token_hash=hashlib.sha256(raw.encode()).hexdigest(),
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=5)))
            db.commit()
        start = threading.Barrier(2)

        def reset(index):
            start.wait(timeout=10)
            return self.http.post("/auth/reset-password", json={
                "token": raw, "new_password": f"Concurrent-test-password-{index}-935!"}).status_code

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(reset, (1, 2)))
        self.assertEqual(sorted(results), [200, 400])
        with SessionLocal() as db:
            self.assertEqual(db.get(User, 1).session_version, 1)
            self.assertEqual(db.query(AuditEvent).filter(AuditEvent.event_type == "user.password_reset").count(), 1)

    def test_failed_reset_keeps_sessions_and_success_invalidates_other_links(self):
        now = datetime.now(timezone.utc)
        raw = "synthetic-expired-reset-not-a-secret"
        other = "synthetic-other-reset-not-a-secret"
        with SessionLocal() as db:
            for token, expiry in ((raw, now - timedelta(seconds=1)), (other, now + timedelta(minutes=5))):
                db.add(PasswordResetToken(user_id=1, token_hash=hashlib.sha256(token.encode()).hexdigest(), expires_at=expiry))
            db.commit()
        self.assert_status(self.http.post("/auth/reset-password", json={
            "token": raw, "new_password": "Synthetic-test-password-935!"}), 400)
        self.assert_status(self.request("GET", "/users/me", user=1), 200)
        self.assert_status(self.reset_fixture_password(1), 200)
        self.assert_status(self.http.post("/auth/reset-password", json={
            "token": other, "new_password": "Synthetic-test-password-935!"}), 400)

    def test_google_and_role_switch_issue_current_generation_without_escalation(self):
        with SessionLocal() as db:
            user = db.get(User, 1)
            user.session_version = 3
            user.account_roles = ["client", "driver"]
            db.commit()
        with patch.object(auth, "_verified_google_email", return_value="fixture1@example.com"):
            response = self.http.post("/auth/google", json={"id_token": "synthetic-google-proof-for-test-only" * 4})
        self.assert_status(response, 200)
        token = response.json()["access_token"]
        self.assertEqual(jwt.decode(token, options={"verify_signature": False})["session_version"], 3)
        switched = self.request("POST", "/auth/switch-role", token=token, json={"role": "driver"})
        self.assert_status(switched, 200)
        switched_token = switched.json()["access_token"]
        self.assert_status(self.request("GET", "/users/me", token=switched_token), 200)
        self.assert_status(self.request("GET", "/admin/users", token=switched_token), 403)
        self.assert_status(self.request("POST", "/auth/switch-role", token=switched_token, json={"role": "admin"}), 422)

    def test_login_does_not_upgrade_a_session_revoked_during_issuance(self):
        real_audit = auth.record_audit_event

        def revoke_before_commit(db, **kwargs):
            if kwargs["event_type"] == "auth.login_succeeded":
                with SessionLocal() as other:
                    user = other.get(User, 1)
                    user.session_version += 1
                    other.commit()
            real_audit(db, **kwargs)

        with patch.object(auth, "record_audit_event", side_effect=revoke_before_commit):
            response = self.http.post("/auth/login", json={"email": "fixture1@example.com", "password": self.password})
        self.assert_status(response, 200)
        self.assert_status(self.request("GET", "/users/me", token=response.json()["access_token"]), 401)

    def test_registration_does_not_inherit_revocation_after_first_commit(self):
        with engine.begin() as connection:
            connection.execute(text("SELECT setval(pg_get_serial_sequence('users', 'id'), 9)"))
        real_refresh = OrmSession.refresh
        revoked = set()

        def refresh_after_revocation(db, instance, *args, **kwargs):
            if isinstance(instance, User):
                # inspect identity without loading expired attributes through this session.
                identity = inspect(instance).identity
                if identity and identity[0] > 9 and identity[0] not in revoked:
                    revoked.add(identity[0])
                    with SessionLocal() as other:
                        other.get(User, identity[0]).session_version += 1
                        other.commit()
            return real_refresh(db, instance, *args, **kwargs)

        for index, route in enumerate(("/auth/register", "/auth/google/register")):
            data = {"full_name": "Synthetic New User", "phone": f"+5691234567{index}",
                    "role": "client", "accepts_terms": True, "accepts_privacy": True}
            if index == 0:
                data.update(email="new-password@example.com", password=self.password)
            else:
                data["id_token"] = "synthetic-google-proof-for-test-only" * 4
            with self.subTest(route=route), patch.object(settings, "PILOT_MODE", False), \
                 patch.object(OrmSession, "refresh", new=refresh_after_revocation), \
                 patch.object(auth, "_verified_google_identity", return_value=("new-google@example.com", "Synthetic New User")):
                response = self.http.post(route, json=data)
            self.assert_status(response, 201)
            self.assert_status(self.request("GET", "/users/me", token=response.json()["access_token"]), 401)
        self.assertEqual(len(revoked), 2)

    def test_chat_delivers_text_images_and_receipts_with_one_database_connection(self):
        small_engine = create_engine(URL, pool_size=1, max_overflow=0, pool_timeout=1)
        self.addCleanup(small_engine.dispose)
        sessions = sessionmaker(bind=small_engine, autoflush=False)
        uploaded = SimpleNamespace(reference="freights/101/chat/synthetic.jpg", content_type="image/jpeg", size_bytes=4)
        with patch.object(database, "SessionLocal", sessions), patch.object(chat, "SessionLocal", sessions):
            with self.http.websocket_connect("/freights/101/chat/live") as ws:
                ws.send_json({"type": "auth", "token": create_access_token({"sub": "3"})})
                self.assertEqual(ws.receive_json()["type"], "ready")
                with ThreadPoolExecutor(max_workers=2) as pool:
                    responses = list(pool.map(lambda index: self.request("POST", "/freights/101/chat/messages",
                        user=1, json={"message_text": f"Concurrent synthetic message {index}"}), (1, 2)))
                for response in responses:
                    self.assert_status(response, 201)
                    self.assertEqual(ws.receive_json()["type"], "message")
                with patch.object(chat, "upload_freight_chat_image", new_callable=AsyncMock, return_value=uploaded):
                    self.assert_status(self.request("POST", "/freights/101/chat/images", user=1,
                        files={"file": ("fixture.jpg", b"test", "image/jpeg")}), 201)
                self.assertEqual(ws.receive_json()["message"]["message_type"], "image")
                self.assert_status(self.request("POST", "/freights/101/chat/read", user=3), 200)
                self.assertEqual(ws.receive_json()["type"], "read")
            self.assertEqual(small_engine.pool.checkedout(), 0)

    def test_stalled_chat_transport_preserves_message_and_notification(self):
        async def blocked_send(_):
            await asyncio.Event().wait()

        manager = chat.freight_chat_connections
        with self.http.websocket_connect("/freights/101/chat/live") as ws:
            ws.send_json({"type": "auth", "token": create_access_token({"sub": "3"})})
            self.assertEqual(ws.receive_json()["type"], "ready")
            sockets = [socket for socket, connection in manager._connections[101].items()
                       if connection.user_id == 3]
            self.assertEqual(len(sockets), 1)
            with patch.object(sockets[0], "send_json", side_effect=blocked_send), \
                 patch("app.services.chat_connections.CHAT_SEND_TIMEOUT_SECONDS", 0.01):
                response = self.request("POST", "/freights/101/chat/messages", user=1,
                    json={"message_text": "Synthetic message retained after slow transport"})
            self.assert_status(response, 201)
            with self.assertRaises(WebSocketDisconnect) as error:
                ws.receive_json()
            self.assertEqual(error.exception.code, 1013)
            self.assertFalse(manager.has_active_user(101, 3))
        self.push.assert_awaited_once()
        self.assertEqual(self.push.call_args.kwargs["recipient_user_id"], 3)
        history = self.request("GET", "/freights/101/chat/messages", user=3)
        self.assert_status(history, 200)
        self.assertIn(response.json()["id"], [message["id"] for message in history.json()])
        self.assert_status(self.request("GET", "/freights/101/chat/messages", user=4), 403)
        with self.http.websocket_connect("/freights/101/chat/live") as ws:
            ws.send_json({"type": "auth", "token": create_access_token({"sub": "3"})})
            self.assertEqual(ws.receive_json()["type"], "ready")
            ws.send_json({"type": "ping"})
            self.assertEqual(ws.receive_json()["type"], "pong")

    def test_detail_and_lists_are_scoped_to_participants(self):
        for user in (1, 3, 5):
            self.assert_status(self.request("GET", "/freights/101", user=user), 200)
        for user in (2, 4):
            self.assert_status(self.request("GET", "/freights/101", user=user), 403)
        for user in (1, 3):
            response = self.request("GET", "/freights", user=user)
            self.assert_status(response, 200)
            self.assertNotIn(102, [row["id"] for row in response.json()])
        self.assert_status(self.request("GET", "/freights/999999", user=1), 404)

    def test_available_requests_require_payment_approval_and_vehicle_match(self):
        for user, expected in ((3, {103}), (6, set()), (8, set()), (9, {103, 105})):
            response = self.request("GET", "/freights?status=available", user=user)
            self.assert_status(response, 200)
            self.assertEqual({row["id"] for row in response.json()}, expected)
        for user, fid, status in ((3, 103, 200), (3, 104, 404), (3, 105, 403), (6, 103, 403)):
            self.assert_status(self.request("GET", f"/freights/{fid}", user=user), status)
        with SessionLocal() as db:
            db.get(Vehicle, 30).approval_status = "pending"
            db.commit()
        self.assertEqual(self.request("GET", "/freights?status=available", user=3).json(), [])
        self.assert_status(self.request("PUT", "/freights/103/accept", user=3), 403)

    def test_acceptance_uses_only_own_compatible_vehicle_and_cannot_be_stolen(self):
        for user, vehicle in ((1, 30), (6, 60), (3, 40), (8, 80)):
            self.assert_status(self.request("PUT", "/freights/103/accept", user=user, json={"vehicle_id": vehicle}), 403)
        self.assert_status(self.request("PUT", "/freights/103/accept", user=3, json={"vehicle_id": 30}), 200)
        self.assert_status(self.request("PUT", "/freights/103/accept", user=4, json={"vehicle_id": 40}), 400)
        with SessionLocal() as db:
            row = db.get(FreightRequest, 103)
            self.assertEqual((row.client_id, row.driver_id, row.actual_vehicle_id, row.client_pays), (1, 30, 30, 12000))

    def test_declined_request_disappears_and_cannot_be_accepted(self):
        self.assert_status(self.request("POST", "/freights/103/decline", user=3), 200)
        self.assertEqual(self.request("GET", "/freights?status=available", user=3).json(), [])
        self.assert_status(self.request("PUT", "/freights/103/accept", user=3), 409)

    def prepare_pickup_home_office(self):
        with SessionLocal() as db:
            freight = db.get(FreightRequest, 103)
            freight.service_type = "home_office"
            freight.selected_vehicle_type = "pickup"
            pickup = db.get(Vehicle, 80)
            pickup.supported_service_types = ["package", "urgent", "home_office"]
            pickup.max_weight_kg = 800
            pickup.max_volume_m3 = 4
            db.commit()

    def assert_pickup_request_unchanged(self):
        with SessionLocal() as db:
            freight = db.get(FreightRequest, 103)
            self.assertEqual(
                (freight.status, freight.driver_id, freight.actual_vehicle_id, freight.client_pays),
                (FreightStatus.pending, None, None, 12000),
            )
            self.assertEqual(freight.payment.status, PaymentStatus.authorized)
            self.assertEqual(db.query(AuditEvent).filter(
                AuditEvent.event_type == "freight.accepted", AuditEvent.entity_id == "103",
            ).count(), 0)

    def test_pickup_confirmation_is_strict_and_persisted_with_actor(self):
        self.prepare_pickup_home_office()
        for value in ("true", "false", 1, 0, None, [], {}):
            with self.subTest(value=value):
                self.assert_status(self.request("PUT", "/freights/103/accept", user=8,
                    json={"vehicle_id": 80, "cargo_safety_acknowledged": value}), 422)
                self.assert_pickup_request_unchanged()
        for payload in ({"vehicle_id": 80}, {"vehicle_id": 80, "cargo_safety_acknowledged": False}):
            self.assert_status(self.request("PUT", "/freights/103/accept", user=8, json=payload), 409)
            self.assert_pickup_request_unchanged()
        self.assert_status(self.request("PUT", "/freights/103/accept", user=8,
            json={"vehicle_id": 80, "cargo_safety_acknowledged": True}), 200)
        with SessionLocal() as db:
            freight = db.get(FreightRequest, 103)
            self.assertEqual((freight.status, freight.driver_id, freight.actual_vehicle_id, freight.client_pays),
                             (FreightStatus.accepted, 80, 80, 12000))
            self.assertIsNotNone(freight.accepted_at)
            self.assertEqual(freight.accepted_at, freight.driver_assigned_at)
            self.assertEqual(freight.accepted_at, freight.driver_accepted_at)
            self.assertEqual(db.query(TripStatusHistory).filter(
                TripStatusHistory.freight_id == 103, TripStatusHistory.status == FreightStatus.accepted,
            ).count(), 1)
            self.assertEqual(freight.payment.status, PaymentStatus.authorized)
            event = db.query(AuditEvent).filter(
                AuditEvent.event_type == "freight.accepted", AuditEvent.entity_id == "103",
            ).one()
            self.assertEqual((event.actor_user_id, event.actor_role), (8, "driver"))
            self.assertIs(event.event_metadata["cargo_safety_acknowledged"], True)
            self.assertEqual(event.event_metadata["cargo_safety_notice_version"], "pickup_home_office_v1")
        self.assert_status(self.request("PUT", "/freights/103/accept", user=8,
            json={"vehicle_id": 80, "cargo_safety_acknowledged": True}), 400)
        with SessionLocal() as db:
            self.assertEqual(db.query(AuditEvent).filter(
                AuditEvent.event_type == "freight.accepted", AuditEvent.entity_id == "103",
            ).count(), 1)

    def test_pickup_confirmation_cannot_override_vehicle_eligibility(self):
        for field, value in (
            ("approval_status", "pending"), ("max_weight_kg", 50), ("max_volume_m3", 0.5),
            ("supported_service_types", ["package", "urgent"]),
        ):
            with self.subTest(field=field):
                self.prepare_pickup_home_office()
                with SessionLocal() as db:
                    pickup = db.get(Vehicle, 80)
                    pickup.approval_status = "approved"
                    setattr(pickup, field, value)
                    db.commit()
                self.assert_status(self.request("PUT", "/freights/103/accept", user=8,
                    json={"vehicle_id": 80, "cargo_safety_acknowledged": True}), 403)
                self.assert_pickup_request_unchanged()

    def test_pickup_confirmation_cannot_override_role_or_vehicle_owner(self):
        self.prepare_pickup_home_office()
        # Keep an approved driver and its compatible vehicle; only the active role changes.
        for role in (UserRole.client, UserRole.admin):
            with self.subTest(role=role):
                with SessionLocal() as db:
                    user = db.get(User, 8)
                    user.role = role
                    user.account_roles = [role.value, "driver"]
                    db.commit()
                self.assert_status(self.request("PUT", "/freights/103/accept", user=8,
                    json={"vehicle_id": 80, "cargo_safety_acknowledged": True}), 403)
                self.assert_pickup_request_unchanged()
        # A different approved driver has the correct active role but does not own this pickup.
        self.assert_status(self.request("PUT", "/freights/103/accept", user=3,
            json={"vehicle_id": 80, "cargo_safety_acknowledged": True}), 403)
        self.assert_pickup_request_unchanged()

    def test_older_app_selects_enclosed_vehicle_without_fabricating_confirmation(self):
        self.prepare_pickup_home_office()
        with SessionLocal() as db:
            db.add(Vehicle(id=81, driver_id=80, type=VehicleType.van, brand="Synthetic",
                model="Enclosed fixture", year=2024, plate="TEST81", color="White",
                max_weight_kg=1000, max_volume_m3=6, approval_status="approved",
                supported_service_types=["home_office"]))
            db.commit()
        self.assert_status(self.request("PUT", "/freights/103/accept", user=8), 200)
        with SessionLocal() as db:
            freight = db.get(FreightRequest, 103)
            self.assertEqual((freight.status, freight.driver_id, freight.actual_vehicle_id, freight.client_pays),
                             (FreightStatus.accepted, 80, 81, 12000))
            self.assertIsNotNone(freight.accepted_at)
            self.assertEqual(freight.accepted_at, freight.driver_assigned_at)
            self.assertEqual(freight.accepted_at, freight.driver_accepted_at)
            self.assertEqual(db.query(TripStatusHistory).filter(
                TripStatusHistory.freight_id == 103, TripStatusHistory.status == FreightStatus.accepted,
            ).count(), 1)
            event = db.query(AuditEvent).filter(
                AuditEvent.event_type == "freight.accepted", AuditEvent.entity_id == "103",
            ).one()
            self.assertIs(event.event_metadata["cargo_safety_acknowledged"], False)
            self.assertIsNone(event.event_metadata["cargo_safety_notice_version"])

    def test_status_and_critical_fields_cannot_be_injected(self):
        for user in (1, 2, 4):
            self.assert_status(self.request("PUT", "/freights/101/status", user=user, json={"status": "in_progress"}), 403)
        for field in ("client_id", "driver_id", "final_price", "client_pays"):
            self.assert_status(self.request("PUT", "/freights/101/status", user=3, json={"status": "in_progress", field: 2}), 422)
        with SessionLocal() as db:
            row = db.get(FreightRequest, 101)
            self.assertEqual((row.status, row.client_id, row.driver_id, row.client_pays), (FreightStatus.accepted, 1, 30, 12000))

    def test_private_cargo_links_require_ownership_and_reject_tampering(self):
        for user in (2, 4):
            self.assert_status(self.request("GET", "/freights/101/cargo-photos", user=user), 403)
        for user in (1, 3, 5):
            self.assert_status(self.request("GET", "/freights/101/cargo-photos", user=user), 200)
        # Available drivers cannot receive signed cargo links until assignment.
        self.assert_status(self.request("GET", "/freights/103/cargo-photos", user=3), 403)
        photo = self.request("GET", "/freights/101/cargo-photos", user=1).json()["photos"][0]
        path = urlsplit(photo["url"]).path
        with patch.object(freights, "stream_private_document", return_value=Response(b"test", media_type="image/jpeg")) as stream:
            self.assert_status(self.request("GET", path), 200)
            stream.assert_called_once_with("freights/101/cargo/test.jpg")
            stream.reset_mock()
            self.assert_status(self.request("GET", path + "tampered"), 404)
            stream.assert_not_called()
            with SessionLocal() as db:
                db.get(FreightCargoPhoto, 301).object_ref = "freights/101/cargo/replaced.jpg"
                db.commit()
            self.assert_status(self.request("GET", path), 404)
            stream.assert_not_called()

    def test_create_rejects_price_owner_assignment_and_status_before_pricing(self):
        payload = {"origin_address": "Synthetic origin", "origin_lat": -33.45, "origin_lng": -70.66,
                   "destination_address": "Synthetic destination", "destination_lat": -33.44,
                   "destination_lng": -70.65, "cargo_description": "Synthetic cargo", "cargo_weight_kg": 100}
        with patch.object(freights, "calculate_pricing_estimate", new_callable=AsyncMock) as pricing:
            for field, value in (("client_id", 2), ("driver_id", 40), ("final_price", 1),
                                 ("client_pays", 1), ("status", "completed")):
                self.assert_status(self.request("POST", "/freights", user=1, json={**payload, field: value}), 422)
            pricing.assert_not_called()
        with SessionLocal() as db:
            self.assertEqual(db.query(FreightRequest).count(), 6)

    def test_chat_participants_can_send_read_and_mark_messages(self):
        response = self.request("POST", "/freights/101/chat/messages", user=3, json={"message_text": "Synthetic reply"})
        self.assert_status(response, 201)
        self.assertEqual(response.json()["receiver_user_id"], 1)
        self.assertEqual(len(self.request("GET", "/freights/101/chat/messages", user=1).json()), 2)
        self.assert_status(self.request("POST", "/freights/101/chat/read", user=1), 200)
        with SessionLocal() as db:
            self.assertIsNotNone(db.get(FreightChatMessage, response.json()["id"]).read_at)
        self.push.assert_awaited_once()

    def test_other_users_and_admin_cannot_participate_in_chat(self):
        for user in (2, 4, 5):
            for method, suffix, payload in (("GET", "messages", None), ("GET", "summary", None),
                                            ("POST", "read", None), ("POST", "messages", {"message_text": "Forbidden"})):
                self.assert_status(self.request(method, f"/freights/101/chat/{suffix}", user=user, **({"json": payload} if payload else {})), 403)
        with SessionLocal() as db:
            self.assertEqual(db.query(FreightChatMessage).count(), 2)
            self.assertIsNone(db.get(FreightChatMessage, 201).read_at)

    def test_admin_chat_review_is_reasoned_read_only_and_audited(self):
        path = "/freights/101/chat/admin-review"
        reason = "Synthetic compliance review for access regression"
        for user in (1, 3):
            self.assert_status(self.request("POST", path, user=user, json={"reason": reason}), 403)
        self.assert_status(self.request("POST", path, user=5, json={"reason": "short"}), 422)
        response = self.request("POST", path, user=5, json={"reason": reason})
        self.assert_status(response, 200)
        self.assertTrue(response.json()["read_only"])
        self.assertEqual([row["id"] for row in response.json()["messages"]], [201])
        with SessionLocal() as db:
            event = db.query(AuditEvent).filter(AuditEvent.event_type == "freight.chat_review_opened").one()
            self.assertEqual((event.actor_user_id, event.reason), (5, reason))
            self.assertIsNone(db.get(FreightChatMessage, 201).read_at)

    def test_chat_images_are_scoped_before_storage_upload(self):
        uploaded = SimpleNamespace(reference="freights/101/chat/synthetic.jpg", content_type="image/jpeg", size_bytes=4)
        with patch.object(chat, "upload_freight_chat_image", new_callable=AsyncMock, return_value=uploaded) as upload:
            for user in (2, 4, 5):
                self.assert_status(self.request("POST", "/freights/101/chat/images", user=user, files={"file": ("fixture.jpg", b"test", "image/jpeg")}), 403)
            upload.assert_not_called()
            response = self.request("POST", "/freights/101/chat/images", user=1, files={"file": ("fixture.jpg", b"test", "image/jpeg")})
            self.assert_status(response, 201)
            upload.assert_awaited_once()
            self.assertNotIn("attachment_ref", response.json())
            self.assertTrue(response.json()["attachment_view_path"].startswith("/freights/chat/images/"))

    def test_completed_chat_is_read_only(self):
        self.assert_status(self.request("GET", "/freights/106/chat/messages", user=1), 200)
        self.assert_status(self.request("POST", "/freights/106/chat/messages", user=1, json={"message_text": "Too late"}), 409)

    def test_websocket_rechecks_identity_and_participation(self):
        for user in (1, 3):
            with self.http.websocket_connect("/freights/101/chat/live") as ws:
                ws.send_json({"type": "auth", "token": create_access_token({"sub": str(user)})})
                self.assertEqual(ws.receive_json()["type"], "ready")
                ws.send_json({"type": "ping"})
                self.assertEqual(ws.receive_json(), {"type": "pong"})
        for user in (2, 4, 5):
            with self.http.websocket_connect("/freights/101/chat/live") as ws:
                ws.send_json({"type": "auth", "token": create_access_token({"sub": str(user)})})
                with self.assertRaises(WebSocketDisconnect) as error:
                    ws.receive_json()
                self.assertEqual(error.exception.code, 4403)
        with self.http.websocket_connect("/freights/101/chat/live") as ws:
            ws.send_json({"type": "auth", "token": "invalid-credential-for-test"})
            with self.assertRaises(WebSocketDisconnect) as error:
                ws.receive_json()
            self.assertEqual(error.exception.code, 4401)

    def test_feedback_is_bilateral_completed_only_and_not_duplicate(self):
        for user, questions in ((1, feedback.CLIENT_QUESTIONS), (3, feedback.DRIVER_QUESTIONS)):
            data = {"overall_score": 5, "answers": {key: 5 for key in questions}}
            self.assert_status(self.request("POST", "/feedback/freights/101", user=user, json=data), 404)
            self.assert_status(self.request("POST", "/feedback/freights/106", user=user, json=data), 201)
            self.assert_status(self.request("POST", "/feedback/freights/106", user=user, json=data), 409)
        for user in (2, 4, 5):
            self.assert_status(self.request("GET", "/feedback/freights/106", user=user), 403)
        with SessionLocal() as db:
            self.assertEqual(db.query(TripFeedback).count(), 2)

    def test_live_location_is_written_by_driver_and_hidden_from_other_users(self):
        payload = {"latitude": -33.45, "longitude": -70.66, "accuracy_m": 10}
        for user in (1, 2, 4, 5):
            self.assert_status(self.request("PUT", "/freights/101/live-location", user=user, json=payload), 403)
        self.assert_status(self.request("PUT", "/freights/101/live-location", user=3, json=payload), 200)
        self.assertTrue(self.request("GET", "/freights/101/live-location", user=1).json()["visible"])
        for user in (2, 4):
            self.assert_status(self.request("GET", "/freights/101/live-location", user=user), 403)

    def test_profile_update_persists_without_role_or_identity_escalation(self):
        self.assert_status(self.request("PUT", "/users/me", user=1, json={"full_name": "Updated Synthetic Name"}), 200)
        self.assertEqual(self.request("GET", "/users/me", user=1).json()["full_name"], "Updated Synthetic Name")
        for field, value in (("id", 2), ("role", "admin"), ("account_roles", ["admin"]), ("email", "fixture2@example.com")):
            self.assert_status(self.request("PUT", "/users/me", user=1, json={field: value}), 422)
        self.assertEqual(self.request("GET", "/users/me", user=2).json()["full_name"], "Synthetic User 2")

    def test_location_is_hidden_before_window_and_after_completion(self):
        with SessionLocal() as db:
            freight = db.get(FreightRequest, 101)
            freight.scheduled_at = datetime.now(timezone.utc) + timedelta(hours=2)
            freight.driver_location_lat = -33.45
            freight.driver_location_lng = -70.66
            freight.driver_location_updated_at = datetime.now(timezone.utc)
            db.commit()
        for status in (FreightStatus.accepted, FreightStatus.completed):
            with SessionLocal() as db:
                db.get(FreightRequest, 101).status = status
                db.commit()
            response = self.request("GET", "/freights/101/live-location", user=1)
            self.assert_status(response, 200)
            self.assertFalse(response.json()["visible"])
            self.assertIsNone(response.json()["latitude"])

    def test_cors_and_sensitive_response_headers(self):
        for origin, status in (("https://muvv-dev.web.app", 200), ("https://untrusted.example", 400)):
            response = self.http.options("/users/me", headers={"Origin": origin, "Access-Control-Request-Method": "GET"})
            self.assert_status(response, status)
            self.assertEqual(response.headers.get("access-control-allow-origin"), origin if status == 200 else None)
        response = self.request("GET", "/users/me", user=1)
        self.assertEqual(response.headers["cache-control"], "no-store")
        self.assertEqual(response.headers["x-content-type-options"], "nosniff")

    def test_admin_documents_and_user_list_are_protected(self):
        for path in ("/admin/users", "/admin/drivers/30/documents/license_image/view-url"):
            for user in (1, 3, 4):
                self.assert_status(self.request("GET", path, user=user), 403)
            self.assert_status(self.request("GET", path, user=5), 200)

    def test_callback_rejects_too_many_form_fields_before_payment_processing(self):
        body = "&".join(f"field{i}=v" for i in range(1001))
        response = self.http.post("/payments/callback", content=body,
                                  headers={"Content-Type": "application/x-www-form-urlencoded"})
        self.assert_status(response, 400)
        self.assertIn("Too many fields", response.json()["detail"])

    def test_callback_rejects_oversized_form_field_before_payment_processing(self):
        response = self.http.post("/payments/callback", content="field=" + "x" * (1024 * 1024 + 1),
                                  headers={"Content-Type": "application/x-www-form-urlencoded"})
        self.assert_status(response, 400)
        self.assertIn("maximum size", response.json()["detail"])

    def test_chat_rejects_oversized_multipart_field(self):
        response = self.request("POST", "/freights/101/chat/images", user=1,
                                files={"caption": (None, "x" * (1024 * 1024 + 1)),
                                       "file": ("synthetic.jpg", b"not-an-image", "image/jpeg")})
        self.assert_status(response, 400)
        self.assertIn("maximum size", response.json()["detail"])

    def webpay_transport(self, *, commit_updates=None, timeout=False):
        self.enterContext(patch.object(settings, "ALLOW_SIMULATED_PAYMENTS", False))
        self.enterContext(patch.object(settings, "TRANSBANK_ENVIRONMENT", "integration"))
        requests = []
        token = "c" * 64

        def handler(request):
            requests.append(request)
            if request.method == "POST":
                return httpx.Response(200, json={
                    "token": token, "url": "https://webpay3gint.transbank.cl/webpayserver/initTransaction",
                })
            if timeout:
                raise httpx.ReadTimeout("Synthetic timeout; no provider contacted")
            created = json.loads(requests[0].content)
            return httpx.Response(200, json={
                "status": "AUTHORIZED", "response_code": 0, "amount": created["amount"],
                "buy_order": created["buy_order"], "authorization_code": "123456",
                "accounting_date": "0910", **(commit_updates or {}),
            })

        def client(**kwargs):
            return REAL_HTTPX_CLIENT(transport=httpx.MockTransport(handler), **kwargs)

        self.enterContext(patch.object(transbank_service.httpx, "Client", side_effect=client))
        return requests, token

    def test_webpay_permissions_backend_amount_and_callback_are_preserved(self):
        requests, token = self.webpay_transport()
        data = {"freight_id": 104, "method": "webpay"}
        for user, expected in ((None, 401), (2, 404), (3, 403), (5, 403)):
            self.assert_status(self.request("POST", "/payments/initiate", user=user, json=data), expected)
        self.assert_status(self.request("POST", "/payments/initiate", user=1,
                                        json={**data, "amount": 1}), 422)
        self.assertEqual(requests, [])
        self.assert_status(self.request("POST", "/payments/initiate", user=1, json=data), 200)
        self.assertEqual(json.loads(requests[0].content)["amount"], 12000)
        self.assert_status(self.http.post("/payments/callback", data={"token_ws": token}, follow_redirects=False), 303)
        with SessionLocal() as db:
            payment = db.query(Payment).filter(Payment.freight_id == 104).one()
            self.assertEqual(payment.status, PaymentStatus.authorized)
            self.assertEqual(payment.amount, 12000)
            self.assertEqual(payment.authorization_code, "123456")
            self.assertIsNotNone(payment.paid_at)
        # Replayed callback must not commit the external operation a second time.
        self.assert_status(self.http.get("/payments/callback", params={"token_ws": token}, follow_redirects=False), 303)
        self.assertEqual(len(requests), 2)

    def test_webpay_mismatched_amount_does_not_authorize(self):
        requests, token = self.webpay_transport(commit_updates={"amount": 1})
        self.assert_status(self.request("POST", "/payments/initiate", user=1,
                                        json={"freight_id": 104, "method": "webpay"}), 200)
        self.assert_status(self.http.post("/payments/callback", data={"token_ws": token}, follow_redirects=False), 303)
        with SessionLocal() as db:
            payment = db.query(Payment).filter(Payment.freight_id == 104).one()
            self.assertEqual(payment.status, PaymentStatus.failed)
            self.assertIsNone(payment.paid_at)
        self.assertEqual(len(requests), 2)

    def test_webpay_timeout_keeps_payment_pending_without_retry(self):
        requests, token = self.webpay_transport(timeout=True)
        self.assert_status(self.request("POST", "/payments/initiate", user=1,
                                        json={"freight_id": 104, "method": "webpay"}), 200)
        self.expected_backend_errors = 1
        response = self.http.post("/payments/callback", data={"token_ws": token})
        self.assert_status(response, 503)
        self.assertNotIn(token, response.text)
        with SessionLocal() as db:
            payment = db.query(Payment).filter(Payment.freight_id == 104).one()
            self.assertEqual(payment.status, PaymentStatus.pending)
            self.assertIsNone(payment.paid_at)
        self.assertEqual(len(requests), 2)

    def test_webpay_wrong_order_or_decline_does_not_authorize(self):
        for updates in ({"buy_order": "other-fixture-order"},
                        {"status": "FAILED", "response_code": -1}, {"response_code": 1}):
            requests, token = self.webpay_transport(commit_updates=updates)
            self.assert_status(self.request("POST", "/payments/initiate", user=1,
                                            json={"freight_id": 104, "method": "webpay"}), 200)
            self.assert_status(self.http.post("/payments/callback", data={"token_ws": token}, follow_redirects=False), 303)
            with SessionLocal() as db:
                payment = db.query(Payment).filter(Payment.freight_id == 104).one()
                self.assertEqual(payment.status, PaymentStatus.failed)
                self.assertIsNone(payment.paid_at)
            self.assertEqual(len(requests), 2)

    def test_webpay_order_only_timeout_cannot_change_payment(self):
        for state in (PaymentStatus.pending, PaymentStatus.authorized, PaymentStatus.refunded):
            with SessionLocal() as db:
                payment = db.query(Payment).filter(Payment.freight_id == 104).one()
                payment.buy_order = "synthetic-known-order"
                payment.status = state
                db.commit()
            for method in ("GET", "POST"):
                data = {"TBK_ORDEN_COMPRA": "synthetic-known-order", "TBK_ID_SESION": "user-1"}
                response = self.http.request(method, "/payments/callback", follow_redirects=False,
                                             **({"params": data} if method == "GET" else {"data": data}))
                self.assert_status(response, 303)
                self.assertTrue(response.headers["location"].endswith("/app/client/freights?payment=unconfirmed"))
                with SessionLocal() as db:
                    self.assertEqual(db.query(Payment).filter(Payment.freight_id == 104).one().status, state)

    def test_webpay_valid_abort_does_not_confirm_or_mutate_financial_state(self):
        requests, token = self.webpay_transport()
        self.assert_status(self.request("POST", "/payments/initiate", user=1,
                                        json={"freight_id": 104, "method": "webpay"}), 200)
        order = json.loads(requests[0].content)["buy_order"]
        for method in ("GET", "POST"):
            data = {"TBK_TOKEN": token, "TBK_ORDEN_COMPRA": order, "TBK_ID_SESION": "user-1"}
            response = self.http.request(method, "/payments/callback", follow_redirects=False,
                                         **({"params": data} if method == "GET" else {"data": data}))
            self.assert_status(response, 303)
            self.assertTrue(response.headers["location"].endswith("104?payment=cancelled"))
        self.assertEqual(len(requests), 1)
        with SessionLocal() as db:
            payment = db.query(Payment).filter(Payment.freight_id == 104).one()
            self.assertEqual(payment.status, PaymentStatus.pending)
            self.assertIsNone(payment.paid_at)
            events = db.query(AuditEvent).filter(AuditEvent.event_type == "payment.checkout_aborted").all()
            self.assertEqual(len(events), 2)
            self.assertNotIn(token, str([event.after_data for event in events]))

    def test_webpay_abort_cannot_mix_token_and_another_order(self):
        requests, token = self.webpay_transport()
        self.assert_status(self.request("POST", "/payments/initiate", user=1,
                                        json={"freight_id": 104, "method": "webpay"}), 200)
        order = json.loads(requests[0].content)["buy_order"]
        with SessionLocal() as db:
            db.query(Payment).filter(Payment.freight_id == 102).update({"buy_order": "other-order"})
            db.commit()
        for data in ({"TBK_TOKEN": token, "TBK_ORDEN_COMPRA": "other-order"},
                     {"TBK_TOKEN": "d" * 64, "TBK_ORDEN_COMPRA": order}):
            self.assert_status(self.http.post("/payments/callback", data=data, follow_redirects=False), 404)
        self.assertEqual(len(requests), 1)
        with SessionLocal() as db:
            self.assertEqual(db.query(Payment).filter(Payment.freight_id == 104).one().status, PaymentStatus.pending)
            self.assertEqual(db.query(Payment).filter(Payment.freight_id == 102).one().status, PaymentStatus.authorized)

    def test_webpay_abort_and_replay_preserve_terminal_payment_states(self):
        requests, token = self.webpay_transport()
        self.assert_status(self.request("POST", "/payments/initiate", user=1,
                                        json={"freight_id": 104, "method": "webpay"}), 200)
        order = json.loads(requests[0].content)["buy_order"]
        paid_at = datetime.now(timezone.utc)
        for state in (PaymentStatus.authorized, PaymentStatus.refunded, PaymentStatus.failed):
            with SessionLocal() as db:
                db.query(Payment).filter(Payment.freight_id == 104).update(
                    {"status": state, "paid_at": paid_at, "authorization_code": "synthetic-auth"})
                db.commit()
            for data in ({"TBK_TOKEN": token, "TBK_ORDEN_COMPRA": order}, {"token_ws": token}):
                response = self.http.post("/payments/callback", data=data, follow_redirects=False)
                self.assert_status(response, 303)
                self.assertEqual(len(requests), 1)
                with SessionLocal() as db:
                    payment = db.query(Payment).filter(Payment.freight_id == 104).one()
                    self.assertEqual(payment.status, state)
                    self.assertEqual(payment.paid_at, paid_at)
                    self.assertEqual(payment.authorization_code, "synthetic-auth")

    def test_webpay_ambiguous_callback_is_rejected_before_processing(self):
        requests, token = self.webpay_transport()
        self.assert_status(self.request("POST", "/payments/initiate", user=1,
                                        json={"freight_id": 104, "method": "webpay"}), 200)
        order = json.loads(requests[0].content)["buy_order"]
        for body in (f"token_ws={token}&token_ws={token}",
                     f"TBK_TOKEN={token}&TBK_ORDEN_COMPRA={order}&TBK_ORDEN_COMPRA=other",
                     f"token_ws={token}&TBK_TOKEN={'d' * 64}&TBK_ORDEN_COMPRA={order}"):
            response = self.http.post("/payments/callback", content=body, follow_redirects=False,
                                      headers={"Content-Type": "application/x-www-form-urlencoded"})
            self.assert_status(response, 400)
        response = self.http.post("/payments/callback", params={"token_ws": token},
                                  data={"token_ws": token}, follow_redirects=False)
        self.assert_status(response, 400)
        self.assertEqual(len(requests), 1)

    def test_webpay_error_return_with_both_tokens_does_not_confirm(self):
        requests, token = self.webpay_transport()
        self.assert_status(self.request("POST", "/payments/initiate", user=1,
                                        json={"freight_id": 104, "method": "webpay"}), 200)
        order = json.loads(requests[0].content)["buy_order"]
        response = self.http.post("/payments/callback", data={
            "token_ws": token, "TBK_TOKEN": token, "TBK_ORDEN_COMPRA": order, "TBK_ID_SESION": "user-1",
        }, follow_redirects=False)
        self.assert_status(response, 303)
        self.assertTrue(response.headers["location"].endswith("104?payment=unconfirmed"))
        self.assertEqual(len(requests), 1)
        with SessionLocal() as db:
            self.assertEqual(db.query(Payment).filter(Payment.freight_id == 104).one().status, PaymentStatus.pending)

    def test_webpay_later_provider_confirmation_can_resolve_aborted_checkout(self):
        requests, token = self.webpay_transport()
        self.assert_status(self.request("POST", "/payments/initiate", user=1,
                                        json={"freight_id": 104, "method": "webpay"}), 200)
        order = json.loads(requests[0].content)["buy_order"]
        self.assert_status(self.http.post("/payments/callback", data={"TBK_TOKEN": token, "TBK_ORDEN_COMPRA": order},
                                         follow_redirects=False), 303)
        self.assertEqual(len(requests), 1)
        self.assert_status(self.http.get("/payments/callback", params={"token_ws": token}, follow_redirects=False), 303)
        self.assertEqual(len(requests), 2)
        with SessionLocal() as db:
            self.assertEqual(db.query(Payment).filter(Payment.freight_id == 104).one().status, PaymentStatus.authorized)

    def test_real_uvicorn_http_and_websocket_on_loopback(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
        server = uvicorn.Server(uvicorn.Config(
            app, host="127.0.0.1", port=port, loop="asyncio", http="h11",
            **websocket_options(), access_log=False, log_level="error", timeout_graceful_shutdown=3,
        ))
        worker = threading.Thread(target=server.run, kwargs={"sockets": [listener]}, daemon=True)
        log_guard = self.assertNoLogs("uvicorn.error", level="ERROR")
        log_guard.__enter__()
        self.addCleanup(log_guard.__exit__, None, None, None)
        worker.start()

        def request(method, path, body=None, token=None):
            headers = {"Content-Type": "application/json"}
            if token:
                headers["Authorization"] = f"Bearer {token}"
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            try:
                connection.request(method, path, json.dumps(body) if body else None, headers)
                response = connection.getresponse()
                return response.status, dict(response.getheaders()), json.loads(response.read())
            finally:
                connection.close()

        try:
            deadline = time.monotonic() + 10
            while not server.started and worker.is_alive() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(server.started, "Local Uvicorn failed to start")
            self.assertEqual(request("GET", "/health")[0], 200)
            for _ in range(20):
                self.assertEqual(request("GET", "/users/me")[0], 401)
            status, _, body = request("POST", "/auth/login", {
                "email": "fixture1@example.com", "password": self.password,
            })
            self.assertEqual(status, 200)
            token = body["access_token"]
            status, headers, body = request("GET", "/users/me", token=token)
            self.assertEqual(status, 200)
            self.assertEqual(headers["cache-control"], "no-store")
            self.assertEqual(body["id"], 1)
            self.assertEqual(request("GET", "/admin/users", token=token)[0], 403)
            self.assertEqual(request("GET", "/freights/102", token=token)[0], 403)
            with websocket_connect(f"ws://127.0.0.1:{port}/freights/101/chat/live",
                                   open_timeout=5, close_timeout=3, proxy=None) as ws:
                ws.send(json.dumps({"type": "auth", "token": token}))
                self.assertEqual(json.loads(ws.recv(timeout=5))["type"], "ready")
                ws.send(json.dumps({"type": "ping"}))
                self.assertEqual(json.loads(ws.recv(timeout=5)), {"type": "pong"})
                self.assertEqual(ws.protocol.extensions, [])
                # Fragmentation must not bypass the aggregate transport limit.
                ws.send(["x" * 8192, "x" * 8193])
                with self.assertRaises(ConnectionClosed) as closed:
                    ws.recv(timeout=5)
                self.assertEqual(closed.exception.rcvd.code, 1009)
            # Oversized first frames are rejected before JSON/authentication too.
            with websocket_connect(f"ws://127.0.0.1:{port}/freights/101/chat/live",
                                   open_timeout=5, close_timeout=3, proxy=None) as ws:
                ws.send("x" * 16385)
                with self.assertRaises(ConnectionClosed) as closed:
                    ws.recv(timeout=5)
                self.assertEqual(closed.exception.rcvd.code, 1009)
        finally:
            server.should_exit = True
            worker.join(timeout=8)
            if worker.is_alive():
                server.force_exit = True
                worker.join(timeout=3)
            listener.close()
            self.assertFalse(worker.is_alive(), "Local Uvicorn did not shut down")
