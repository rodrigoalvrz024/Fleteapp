import os
import unittest
from datetime import datetime, timezone

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost/fleteapp_test",
)
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.models.freight import FreightRequest, FreightStatus
from app.models.payment import Payment, PaymentMethod, PaymentStatus
from app.models.rating import Rating
from app.schemas.freight import FreightResponse, FreightStatusUpdate
from app.services.freight_service import can_transition
from app.services.storage_service import _detect_upload_type


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


if __name__ == "__main__":
    unittest.main()
