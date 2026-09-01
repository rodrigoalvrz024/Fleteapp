import os
import unittest

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

from fastapi import HTTPException

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost/muvv_test",
)
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.models.driver import Driver, DriverStatus
from app.models.freight_driver_decline import FreightDriverDecline
from app.models.freight import FreightRequest, FreightStatus
from app.models.payment import Payment, PaymentMethod, PaymentStatus
from app.models.user import User, UserRole
from app.models.vehicle import Vehicle, VehicleApprovalStatus, VehicleType
from app.routers.freights import (
    _live_location_response,
    _live_location_window,
    _require_freight_view_access,
    _require_live_location_view_access,
)


class FreightAccessTests(unittest.TestCase):
    @staticmethod
    def _authorized_payment(freight: FreightRequest) -> Payment:
        payment = Payment(
            id=1,
            freight_id=freight.id,
            amount=10000,
            method=PaymentMethod.webpay,
            status=PaymentStatus.authorized,
        )
        freight.payment = payment
        return payment

    def _db_with_driver(self, driver: Driver):
        db = MagicMock()
        driver_query = MagicMock()
        driver_query.filter.return_value.first.return_value = driver
        decline_query = MagicMock()
        decline_query.filter.return_value.first.return_value = None

        def query(model):
            return (
                decline_query
                if getattr(model, "class_", None) is FreightDriverDecline
                else driver_query
            )

        db.query.side_effect = query
        return db

    def _operational_driver(self, user_id: int) -> Driver:
        future = datetime.now(timezone.utc) + timedelta(days=60)
        driver = Driver(
            id=5,
            user_id=user_id,
            rut="12345678-9",
            license_number="B-123456",
            license_expiry=future,
            license_image_url="drivers/5/license.jpg",
            circulation_permit_url="drivers/5/permit.jpg",
            circulation_permit_expiry=future,
            technical_review_url="drivers/5/technical.jpg",
            technical_review_expiry=future,
            soap_url="drivers/5/soap.jpg",
            soap_expiry=future,
            status=DriverStatus.approved,
        )
        driver.vehicle = Vehicle(
            id=3,
            driver_id=driver.id,
            type=VehicleType.pickup,
            brand="Toyota",
            model="Hilux",
            year=2022,
            plate="ABCD12",
            color="Blanco",
            max_weight_kg=800,
            approval_status=VehicleApprovalStatus.approved.value,
        )
        return driver

    def test_approved_driver_can_view_available_pending_freight(self):
        user = User(id=10, role=UserRole.driver)
        driver = self._operational_driver(user.id)
        freight = FreightRequest(
            id=12,
            client_id=3,
            driver_id=None,
            status=FreightStatus.pending,
        )
        self._authorized_payment(freight)

        _require_freight_view_access(freight, self._db_with_driver(driver), user)

    def test_driver_cannot_view_unpaid_available_freight(self):
        user = User(id=10, role=UserRole.driver)
        driver = self._operational_driver(user.id)
        freight = FreightRequest(
            id=15,
            client_id=3,
            driver_id=None,
            status=FreightStatus.pending,
        )

        with self.assertRaises(HTTPException) as error:
            _require_freight_view_access(freight, self._db_with_driver(driver), user)

        self.assertEqual(error.exception.status_code, 404)

    def test_pending_driver_cannot_view_available_freight_detail(self):
        user = User(id=11, role=UserRole.driver)
        driver = Driver(id=6, user_id=user.id, status=DriverStatus.pending)
        freight = FreightRequest(
            id=13,
            client_id=3,
            driver_id=None,
            status=FreightStatus.pending,
        )

        with self.assertRaises(HTTPException) as error:
            _require_freight_view_access(freight, self._db_with_driver(driver), user)

        self.assertEqual(error.exception.status_code, 403)

    def test_approved_driver_with_missing_documents_cannot_view_available_detail(self):
        user = User(id=12, role=UserRole.driver)
        driver = Driver(
            id=7,
            user_id=user.id,
            rut="11111111-1",
            license_number="B-789",
            license_expiry=datetime.now(timezone.utc) + timedelta(days=60),
            status=DriverStatus.approved,
        )
        freight = FreightRequest(
            id=14,
            client_id=3,
            driver_id=None,
            status=FreightStatus.pending,
        )

        with self.assertRaises(HTTPException) as error:
            _require_freight_view_access(freight, self._db_with_driver(driver), user)

        self.assertEqual(error.exception.status_code, 403)
        self.assertIn("blockers", error.exception.detail)

    def test_scheduled_freight_hides_location_until_the_pre_service_window(self):
        now = datetime.now(timezone.utc)
        freight = FreightRequest(
            id=20,
            client_id=3,
            driver_id=5,
            status=FreightStatus.accepted,
            is_urgent=False,
            scheduled_at=now + timedelta(minutes=45),
            driver_location_lat=-33.45,
            driver_location_lng=-70.66,
            driver_location_updated_at=now,
        )

        visible, available_from = _live_location_window(freight, now)
        response = _live_location_response(freight, now)

        self.assertFalse(visible)
        self.assertIsNotNone(available_from)
        self.assertFalse(response.visible)
        self.assertIsNone(response.latitude)

    def test_only_active_assigned_freight_exposes_last_driver_position(self):
        now = datetime.now(timezone.utc)
        freight = FreightRequest(
            id=21,
            client_id=3,
            driver_id=5,
            status=FreightStatus.in_progress,
            is_urgent=True,
            driver_location_lat=-33.45,
            driver_location_lng=-70.66,
            driver_location_accuracy_m=12,
            driver_location_updated_at=now,
        )

        response = _live_location_response(freight, now)
        self.assertTrue(response.visible)
        self.assertEqual(response.latitude, -33.45)

        freight.status = FreightStatus.completed
        completed = _live_location_response(freight, now)
        self.assertFalse(completed.visible)
        self.assertIsNone(completed.latitude)

    def test_other_client_cannot_view_assigned_driver_location(self):
        freight = FreightRequest(
            id=22,
            client_id=3,
            driver_id=5,
            status=FreightStatus.accepted,
        )
        unrelated_client = User(id=4, role=UserRole.client)

        with self.assertRaises(HTTPException) as error:
            _require_live_location_view_access(freight, MagicMock(), unrelated_client)

        self.assertEqual(error.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()
