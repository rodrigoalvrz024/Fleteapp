import os
import unittest
from unittest.mock import MagicMock

from fastapi import HTTPException

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost/fleteapp_test",
)
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest, FreightStatus
from app.models.user import User, UserRole
from app.routers.freights import _require_freight_view_access


class FreightAccessTests(unittest.TestCase):
    def _db_with_driver(self, driver: Driver):
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = driver
        return db

    def test_approved_driver_can_view_available_pending_freight(self):
        user = User(id=10, role=UserRole.driver)
        driver = Driver(id=5, user_id=user.id, status=DriverStatus.approved)
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


if __name__ == "__main__":
    unittest.main()
