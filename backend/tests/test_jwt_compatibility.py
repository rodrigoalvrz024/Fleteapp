"""JWT migration fixtures are synthetic and never authorize a real account."""

import os
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("SECRET_KEY", "synthetic-jwt-test-key-with-at-least-32-bytes")
os.environ.setdefault("DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:1/muvv_test")

import jwt
from fastapi import HTTPException

from app.core.config import settings
from app.core.security import create_access_token, decode_token
from app.services import storage_service as storage


FIXTURE_KEY = "synthetic-jose-compatibility-key-not-a-secret"
# Generated with python-jose 3.3.0, using the public synthetic key above.
JOSE_ACCESS = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJzdWIiOiIxMjMiLCJleHAiOjQxMDI0NDQ4MDAsImlhdCI6MTcwNDA2NzIwMCwiaXNzIjoibXV2di1hcGkiLCJhdWQiOiJtdXZ2LWFwcCIsInRva2VuX3R5cGUiOiJhY2Nlc3MiLCJyb2xlIjoiY2xpZW50In0."
    "C4OuqEyW4T3PcY-6WnlA_uGzCfWvDThWDyqwrQUxtLw"
)
JOSE_DOCUMENT = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJwdXJwb3NlIjoiZHJpdmVyX2RvY3VtZW50X3ZpZXciLCJkcml2ZXJfaWQiOjcsImRvY3VtZW50X3R5cGUiOiJsaWNlbnNlX2ltYWdlIiwiZG9jdW1lbnRfcmVmIjoiZHJpdmVycy83L3N5bnRoZXRpYy5qcGciLCJleHAiOjQxMDI0NDQ4MDB9."
    "GcJekIViCx3I1VEhVS_lS1-sjrFw6xlgtkLSx6IJYVA"
)
PRIVATE_CASES = (
    (storage.create_driver_document_view_token, storage.decode_driver_document_view_token,
     (7, "license_image", "drivers/7/synthetic.jpg"), storage.DOCUMENT_VIEW_PURPOSE),
    (storage.create_freight_evidence_view_token, storage.decode_freight_evidence_view_token,
     (9, "delivery", "freights/9/synthetic.jpg"), storage.FREIGHT_EVIDENCE_VIEW_PURPOSE),
    (storage.create_cargo_photo_view_token, storage.decode_cargo_photo_view_token,
     (9, 12, "freights/9/cargo/synthetic.jpg"), storage.CARGO_PHOTO_VIEW_PURPOSE),
    (storage.create_chat_image_view_token, storage.decode_chat_image_view_token,
     (9, 13, "freights/9/chat/synthetic.jpg"), storage.CHAT_IMAGE_VIEW_PURPOSE),
)


class JwtCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(settings, "SECRET_KEY", FIXTURE_KEY))
        self.enterContext(patch.object(settings, "JWT_ISSUER", "muvv-api"))
        self.enterContext(patch.object(settings, "JWT_AUDIENCE", "muvv-app"))

    def claims(self):
        return decode_token(create_access_token({"sub": "123", "role": "client"}))

    def assert_denied(self, decode, token, status):
        with self.assertRaises(HTTPException) as error:
            decode(token)
        self.assertEqual(error.exception.status_code, status)

    def test_existing_jose_access_token_remains_valid(self):
        self.assertEqual(decode_token(JOSE_ACCESS)["sub"], "123")

    def test_existing_jose_private_document_link_remains_valid(self):
        self.assertEqual(storage.decode_driver_document_view_token(JOSE_DOCUMENT)["driver_id"], 7)

    def test_access_requires_expiry_identity_and_issuer_claims(self):
        for field in ("exp", "iat", "iss", "aud", "sub", "token_type"):
            with self.subTest(field=field):
                claims = self.claims()
                del claims[field]
                self.assert_denied(decode_token, jwt.encode(claims, FIXTURE_KEY, algorithm="HS256"), 401)

    def test_wrong_algorithm_unsigned_and_wrong_signature_are_denied(self):
        claims = self.claims()
        self.enterContext(patch.object(settings, "SECRET_KEY", FIXTURE_KEY * 2))
        for token in (
            jwt.encode(claims, FIXTURE_KEY * 2, algorithm="HS384"),
            jwt.encode(claims, "", algorithm="none"),
            jwt.encode(claims, "another-synthetic-key-at-least-32-bytes", algorithm="HS256"),
        ):
            self.assert_denied(decode_token, token, 401)

    def test_wrong_issuer_and_future_issued_token_are_denied(self):
        for field, value in (("iss", "not-muvv"), ("iat", 4102444800)):
            claims = self.claims()
            claims[field] = value
            self.assert_denied(decode_token, jwt.encode(claims, FIXTURE_KEY, algorithm="HS256"), 401)

    def test_private_links_round_trip_and_cannot_authenticate(self):
        for create, decode, args, purpose in PRIVATE_CASES:
            with self.subTest(purpose=purpose):
                token, _ = create(*args)
                self.assertEqual(decode(token)["purpose"], purpose)
                self.assert_denied(decode_token, token, 401)

    def test_private_links_reject_expired_missing_expiry_and_wrong_purpose(self):
        for create, decode, args, purpose in PRIVATE_CASES:
            token, _ = create(*args)
            original = decode(token)
            for change in ("expired", "missing", "purpose"):
                with self.subTest(purpose=purpose, change=change):
                    claims = original.copy()
                    if change == "expired":
                        claims["exp"] = datetime.now(timezone.utc) - timedelta(seconds=5)
                    elif change == "missing":
                        del claims["exp"]
                    else:
                        claims["purpose"] = "not-muvv"
                    invalid = jwt.encode(claims, storage._view_token_key(purpose), algorithm="HS256")
                    self.assert_denied(decode, invalid, 404)

    def test_private_links_are_not_interchangeable(self):
        access = create_access_token({"sub": "123"})
        for create, _, args, purpose in PRIVATE_CASES:
            token, _ = create(*args)
            for _, decode, _, other_purpose in PRIVATE_CASES:
                self.assert_denied(decode, access, 404)
                if purpose != other_purpose:
                    self.assert_denied(decode, token, 404)

    def test_malformed_tokens_use_generic_errors(self):
        for token in ("", "not.jwt", "a.b.c", "[]", "e30.W10.invalid"):
            self.assert_denied(decode_token, token, 401)
            for _, decode, _, _ in PRIVATE_CASES:
                self.assert_denied(decode, token, 404)
