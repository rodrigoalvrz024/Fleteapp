import os
import unittest

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

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
    get_driver_live_location,
    update_driver_live_location,
)
from app.schemas.freight import DriverLocationUpdate


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

    def test_accepted_freight_hides_location_without_an_early_access_window(self):
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
        self.assertIsNone(available_from)
        self.assertFalse(response.visible)
        self.assertIsNone(response.latitude)

    def test_only_started_trips_expose_location_regardless_of_schedule(self):
        now = datetime.now(timezone.utc)
        for status in FreightStatus:
            for urgent in (True, False):
                for offset in (-120, 0, 10, 120):
                    with self.subTest(status=status, urgent=urgent, offset=offset):
                        freight = FreightRequest(
                            id=23, client_id=3, driver_id=5, status=status,
                            is_urgent=urgent, scheduled_at=now + timedelta(minutes=offset),
                            driver_location_lat=-33.45, driver_location_lng=-70.66,
                            driver_location_accuracy_m=12, driver_location_heading=90,
                            driver_location_updated_at=now,
                        )
                        response = _live_location_response(freight, now)
                        self.assertEqual(response.visible, status == FreightStatus.in_progress)
                        self.assertIsNone(response.available_from)
                        if not response.visible:
                            for field in ("latitude", "longitude", "accuracy_m", "heading", "updated_at"):
                                self.assertIsNone(getattr(response, field))
                        freight.driver_id = None
                        self.assertFalse(_live_location_response(freight, now).visible)

    def test_endpoint_blocks_legacy_driver_updates_before_start_and_after_close(self):
        driver = Driver(id=5, user_id=10)
        freight = FreightRequest(id=24, client_id=3, driver_id=5)
        db = MagicMock()
        def query(model):
            result = MagicMock()
            result.filter.return_value.first.return_value = freight if model is FreightRequest else driver
            return result
        db.query.side_effect = query
        data = DriverLocationUpdate(latitude=-33.45, longitude=-70.66, accuracy_m=10)
        for status in (FreightStatus.pending, FreightStatus.accepted,
                       FreightStatus.completed, FreightStatus.cancelled):
            freight.status = status
            with self.subTest(status=status), patch("app.routers.freights.check_rate_limit"):
                with self.assertRaises(HTTPException) as error:
                    update_driver_live_location(24, data, MagicMock(), db, User(id=10, role=UserRole.driver))
                self.assertEqual(error.exception.status_code, 409)
                self.assertIsNone(freight.driver_location_lat)
                db.commit.assert_not_called()
        freight.status = FreightStatus.in_progress
        with patch("app.routers.freights.check_rate_limit"):
            response = update_driver_live_location(24, data, MagicMock(), db, User(id=10, role=UserRole.driver))
        self.assertTrue(response.visible)
        db.commit.assert_called_once()

    def test_get_hides_old_coordinates_and_keeps_owner_and_role_checks(self):
        freight = FreightRequest(id=25, client_id=3, driver_id=5,
            status=FreightStatus.accepted, driver_location_lat=-33.45,
            driver_location_lng=-70.66, driver_location_updated_at=datetime.now(timezone.utc))
        db = MagicMock()
        driver = Driver(id=5, user_id=10)
        def query(model):
            result = MagicMock()
            result.filter.return_value.first.return_value = freight if model is FreightRequest else driver
            return result
        db.query.side_effect = query
        for user in (User(id=3, role=UserRole.client), User(id=10, role=UserRole.driver),
                     User(id=1, role=UserRole.admin)):
            with patch("app.routers.freights.record_audit_event"):
                result = get_driver_live_location(25, MagicMock(), db, user)
            self.assertFalse(result.visible)
            self.assertIsNone(result.latitude)
        for user in (User(id=4, role=UserRole.client), User(id=11, role=UserRole.driver)):
            driver.id = 6
            with self.assertRaises(HTTPException) as error:
                get_driver_live_location(25, MagicMock(), db, user)
            self.assertEqual(error.exception.status_code, 403)

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
