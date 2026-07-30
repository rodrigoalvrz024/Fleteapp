import os
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

from fastapi import HTTPException

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost/muvv_test",
)
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest, FreightStatus
from app.models.user import User, UserRole
from app.models.vehicle import Vehicle, VehicleType
from app.routers.freights import _require_freight_view_access


class FreightAccessTests(unittest.TestCase):
    def _db_with_driver(self, driver: Driver):
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = driver
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

        _require_freight_view_access(freight, self._db_with_driver(driver), user)

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


if __name__ == "__main__":
    unittest.main()
