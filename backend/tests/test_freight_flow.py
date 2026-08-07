import os
import unittest
from datetime import datetime, timezone
from unittest.mock import Mock, patch

from fastapi import HTTPException

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost/muvv_test",
)
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.models.freight import FreightRequest, FreightStatus
from app.models.payment import Payment, PaymentMethod, PaymentStatus
from app.models.rating import Rating
from app.schemas.freight import FreightCreateResponse, FreightResponse, FreightStatusUpdate
from app.core.config import settings
from app.services.freight_service import can_transition
from app.services.storage_service import (
    _detect_upload_type,
    _normalize_document_ref,
    _strip_image_metadata,
    _upload_private_object,
)


class FreightCompletionFlowTests(unittest.TestCase):
    def _freight(self) -> FreightRequest:
        return FreightRequest(
            id=7,
            client_id=3,
            driver_id=2,
            origin_address="Origen",
            origin_lat=-33.4,
            origin_lng=-70.6,
            destination_address="Destino",
            destination_lat=-33.5,
            destination_lng=-70.7,
            cargo_description="Carga",
            cargo_weight_kg=10,
            requires_helpers=0,
            is_urgent=False,
            status=FreightStatus.completed,
            created_at=datetime.now(timezone.utc),
            pickup_photo_ref="freights/7/evidence/pickup/a.jpg",
            delivery_photo_ref="freights/7/evidence/delivery/b.jpg",
            delivery_pin_hash="never-expose-this",
            delivery_pin_verified_at=datetime.now(timezone.utc),
        )

    def test_response_exposes_operational_summary_without_pin_hash(self):
        freight = self._freight()
        freight.payment = Payment(
            id=5,
            freight_id=freight.id,
            amount=32000,
            method=PaymentMethod.webpay,
            status=PaymentStatus.authorized,
        )
        freight.rating = Rating(
            id=4,
            freight_id=freight.id,
            rater_id=freight.client_id,
            rated_driver_id=freight.driver_id,
            score=5,
            comment="Excelente",
        )

        response = FreightResponse.model_validate(freight).model_dump()

        self.assertTrue(response["has_pickup_photo"])
        self.assertTrue(response["has_delivery_photo"])
        self.assertTrue(response["delivery_pin_ready"])
        self.assertTrue(response["delivery_pin_verified"])
        self.assertEqual(response["payment_status"], "authorized")
        self.assertEqual(response["rating_score"], 5)
        self.assertNotIn("delivery_pin_hash", response)

    def test_completion_request_accepts_confirmation_pin(self):
        request = FreightStatusUpdate(
            status=FreightStatus.completed,
            confirmation_pin="1234",
        )
        self.assertEqual(request.confirmation_pin, "1234")

    def test_create_response_keeps_relationship_fields_out(self):
        freight = self._freight()
        response = FreightCreateResponse.model_validate(freight).model_dump()

        self.assertEqual(response["id"], freight.id)
        self.assertTrue(response["has_pickup_photo"])
        self.assertNotIn("status_history", response)
        self.assertNotIn("payment_status", response)
        self.assertNotIn("rating_score", response)
        self.assertNotIn("driver_summary", response)

    def test_completion_transition_is_only_allowed_from_in_progress(self):
        self.assertTrue(
            can_transition(FreightStatus.in_progress, FreightStatus.completed)
        )
        self.assertFalse(can_transition(FreightStatus.accepted, FreightStatus.completed))

    def test_storage_detects_jpeg_even_when_browser_sends_octet_stream(self):
        content = b"\xff\xd8\xff\xe0" + b"jpeg"
        self.assertEqual(
            _detect_upload_type(content, "application/octet-stream", "foto"),
            "image/jpeg",
        )

    def test_storage_detects_heic_for_ios_photos(self):
        content = b"\x00\x00\x00\x18ftypheic\x00\x00\x00\x00mif1"
        self.assertEqual(
            _detect_upload_type(content, "application/octet-stream", "foto.HEIC"),
            "image/heic",
        )

    def test_storage_strips_jpeg_metadata_before_private_upload(self):
        metadata = b"Exif\x00\x00GPS LOCATION"
        content = (
            b"\xff\xd8"
            b"\xff\xe1"
            + (len(metadata) + 2).to_bytes(2, "big")
            + metadata
            + b"\xff\xda"
            + b"\x00\x08scan-bytes"
        )

        stripped = _strip_image_metadata("image/jpeg", content)

        self.assertTrue(stripped.startswith(b"\xff\xd8"))
        self.assertIn(b"\xff\xda", stripped)
        self.assertNotIn(b"GPS LOCATION", stripped)

    def test_storage_uploads_to_private_supabase_bucket(self):
        response = Mock(status_code=201)
        with (
            patch.object(settings, "DRIVER_DOCUMENTS_BUCKET", "muvv-private"),
            patch.object(settings, "SUPABASE_URL", "https://example.supabase.co"),
            patch.object(settings, "SUPABASE_SERVICE_ROLE_KEY", "service-key"),
            patch("app.services.storage_service.httpx.post", return_value=response) as post,
        ):
            _upload_private_object(
                "freights/7/evidence/pickup/photo.jpg",
                b"image-bytes",
                "image/jpeg",
            )

        post.assert_called_once()
        url, = post.call_args.args
        self.assertEqual(
            url,
            "https://example.supabase.co/storage/v1/object/muvv-private/"
            "freights/7/evidence/pickup/photo.jpg",
        )
        self.assertEqual(post.call_args.kwargs["headers"]["Content-Type"], "image/jpeg")
        self.assertEqual(
            post.call_args.kwargs["headers"]["Authorization"],
            "Bearer service-key",
        )

    def test_storage_uses_new_supabase_secret_key_as_api_key(self):
        response = Mock(status_code=201)
        with (
            patch.object(settings, "DRIVER_DOCUMENTS_BUCKET", "muvv-private"),
            patch.object(settings, "SUPABASE_URL", "https://example.supabase.co"),
            patch.object(settings, "SUPABASE_SERVICE_ROLE_KEY", "sb_secret_test"),
            patch("app.services.storage_service.httpx.post", return_value=response) as post,
        ):
            _upload_private_object("drivers/7/license/photo.jpg", b"image-bytes", "image/jpeg")

        headers = post.call_args.kwargs["headers"]
        self.assertEqual(headers["apikey"], "sb_secret_test")
        self.assertNotIn("Authorization", headers)

    def test_storage_rejects_old_google_cloud_references(self):
        with self.assertRaises(HTTPException) as context:
            _normalize_document_ref("gs://old-project-private/drivers/7/license.jpg")

        self.assertEqual(context.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
