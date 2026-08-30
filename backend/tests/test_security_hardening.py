import os
import unittest
from datetime import datetime, timedelta, timezone
from io import BytesIO

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost/muvv_test",
)
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from fastapi import HTTPException
from jose import jwt
from starlette.datastructures import UploadFile

from app.core.config import Settings, settings
from app.core.rate_limit import _client_ip
from app.core.security import create_access_token, decode_token, require_role
from app.models.freight import FreightRequest, FreightStatus
from app.models.user import User, UserRole
from app.routers.freights import _require_freight_status_access
from app.routers.analytics import _clean_event_metadata
from app.routers.users import _redact_user_audit_data
from app.schemas.freight import FreightCreate, FreightStatusUpdate
from app.schemas.user import UserCreate
from app.services.storage_service import (
    create_driver_document_view_token,
    decode_driver_document_view_token,
    upload_driver_document,
)


class SecurityHardeningTests(unittest.TestCase):
    def test_user_audit_redacts_fcm_token(self):
        data = {
            "full_name": "Conductor Demo",
            "fcm_token": "secret-device-token",
        }

        redacted = _redact_user_audit_data(data)

        self.assertEqual(redacted["full_name"], "Conductor Demo")
        self.assertEqual(redacted["fcm_token"], "[redacted]")
        self.assertEqual(data["fcm_token"], "secret-device-token")

    def test_access_token_has_audience_and_rejects_legacy_payload(self):
        token = create_access_token({"sub": "123", "role": "client"})
        payload = decode_token(token)
        self.assertEqual(payload["sub"], "123")
        self.assertEqual(payload["token_type"], "access")

        legacy_token = jwt.encode(
            {
                "sub": "123",
                "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
            },
            settings.SECRET_KEY,
            algorithm=settings.ALGORITHM,
        )
        with self.assertRaises(HTTPException) as error:
            decode_token(legacy_token)
        self.assertEqual(error.exception.status_code, 401)

    def test_document_link_token_cannot_be_used_as_an_access_token(self):
        document_token, _ = create_driver_document_view_token(
            driver_id=7,
            document_type="license_image",
            document_ref="drivers/7/license/example.jpg",
        )
        self.assertEqual(
            decode_driver_document_view_token(document_token)["driver_id"],
            7,
        )
        with self.assertRaises(HTTPException) as error:
            decode_token(document_token)
        self.assertEqual(error.exception.status_code, 401)

    def test_public_registration_cannot_create_an_admin(self):
        with self.assertRaises(ValueError):
            UserCreate.model_validate(
                {
                    "email": "admin@example.com",
                    "phone": "+56 9 1234 5678",
                    "full_name": "Admin Intent",
                    "password": "password-segura",
                    "role": "admin",
                }
            )

    def test_pilot_allowlist_normalizes_addresses(self):
        original = settings.PILOT_ALLOWED_EMAILS
        try:
            settings.PILOT_ALLOWED_EMAILS = " Cliente@Example.com, driver@example.com , "
            self.assertEqual(
                settings.pilot_allowed_emails,
                {"cliente@example.com", "driver@example.com"},
            )
        finally:
            settings.PILOT_ALLOWED_EMAILS = original

    def test_production_push_requires_valid_firebase_credentials(self):
        production_settings = {
            "APP_ENV": "production",
            "DATABASE_URL": "postgresql://postgres:postgres@localhost/muvv_test",
            "SECRET_KEY": "x" * 48,
            "CORS_ORIGINS": "https://muvv-dev.web.app",
            "PILOT_MODE": False,
            "ENABLE_DRIVER_PUSH_NOTIFICATIONS": True,
        }
        with self.assertRaises(ValueError):
            Settings(**production_settings)

        configured = Settings(
            **production_settings,
            FIREBASE_CREDENTIALS_JSON='{"client_email":"muvv@example.iam.gserviceaccount.com"}',
        )
        self.assertTrue(configured.ENABLE_DRIVER_PUSH_NOTIFICATIONS)

    def test_freight_input_rejects_out_of_range_coordinates_and_pin(self):
        with self.assertRaises(ValueError):
            FreightCreate.model_validate(
                {
                    "origin_address": "Origen valido",
                    "origin_lat": 100,
                    "origin_lng": -70,
                    "destination_address": "Destino valido",
                    "destination_lat": -33,
                    "destination_lng": -70,
                    "cargo_description": "Cajas",
                    "cargo_weight_kg": 10,
                }
            )
        with self.assertRaises(ValueError):
            FreightStatusUpdate.model_validate(
                {"status": "completed", "confirmation_pin": "12345"}
            )

    def test_client_ip_uses_the_proxy_appended_value(self):
        class RequestStub:
            headers = {"x-forwarded-for": "forged, 203.0.113.10"}
            client = None

        self.assertEqual(_client_ip(RequestStub()), "203.0.113.10")

    def test_document_upload_stops_after_configured_limit(self):
        oversized = BytesIO(b"x" * (settings.DRIVER_DOCUMENT_MAX_MB * 1024 * 1024 + 1))
        upload = UploadFile(filename="large.jpg", file=oversized)

        with self.assertRaises(HTTPException) as error:
            import asyncio

            asyncio.run(upload_driver_document(upload, 1, "license_image"))
        self.assertEqual(error.exception.status_code, 400)

    def test_admin_role_is_not_available_to_client_or_driver(self):
        admin_only = require_role("admin")
        admin_only(User(id=1, role=UserRole.admin))

        for role in (UserRole.client, UserRole.driver):
            with self.subTest(role=role), self.assertRaises(HTTPException) as error:
                admin_only(User(id=2, role=role))
            self.assertEqual(error.exception.status_code, 403)

    def test_only_freight_owner_can_cancel_as_client(self):
        freight = FreightRequest(
            id=8,
            client_id=100,
            status=FreightStatus.pending,
        )
        owner = User(id=100, role=UserRole.client)
        other_client = User(id=101, role=UserRole.client)
        admin = User(id=102, role=UserRole.admin)

        _require_freight_status_access(
            freight,
            None,
            owner,
            FreightStatus.cancelled,
        )
        _require_freight_status_access(
            freight,
            None,
            admin,
            FreightStatus.cancelled,
        )
        with self.assertRaises(HTTPException) as error:
            _require_freight_status_access(
                freight,
                None,
                other_client,
                FreightStatus.cancelled,
            )
        self.assertEqual(error.exception.status_code, 403)

    def test_screen_analytics_only_keeps_safe_aggregate_metadata(self):
        metadata = _clean_event_metadata(
            "app.screen_dwell",
            {
                "screen": "/app/client/freights/:id",
                "duration_seconds": 42,
                "email": "private@example.com",
                "message": "texto privado",
            },
        )

        self.assertEqual(metadata["screen"], "/app/client/freights/:id")
        self.assertEqual(metadata["duration_seconds"], 42)
        self.assertNotIn("email", metadata)
        self.assertNotIn("message", metadata)

    def test_screen_analytics_rejects_invalid_duration(self):
        with self.assertRaises(HTTPException) as error:
            _clean_event_metadata(
                "app.screen_dwell",
                {"screen": "/app/client", "duration_seconds": "mucho"},
            )
        self.assertEqual(error.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main()
