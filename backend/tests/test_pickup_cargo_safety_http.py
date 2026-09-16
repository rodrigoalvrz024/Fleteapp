import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock

from tests import test_pricing_service  # Configure isolated settings before app imports.
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.security import get_current_user
from app.database import get_db
from app.models.user import UserRole
from app.routers.freights import router


class PickupCargoSafetyHttpTests(unittest.TestCase):
    def setUp(self):
        self.db = MagicMock()
        self.app = FastAPI()
        self.app.include_router(router)
        self.app.dependency_overrides[get_db] = lambda: self.db
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)

    def _as_role(self, role):
        self.app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
            id=7, role=role, account_roles=["client", "driver"],
        )

    def test_anonymous_confirmation_does_not_grant_access(self):
        response = self.client.put(
            "/freights/109/accept", json={"cargo_safety_acknowledged": True},
        )
        self.assertEqual(response.status_code, 401)
        self.db.query.assert_not_called()
        self.db.commit.assert_not_called()

    def test_confirmation_does_not_bypass_active_role(self):
        for role in (UserRole.client, UserRole.admin):
            with self.subTest(role=role):
                self._as_role(role)
                response = self.client.put(
                    "/freights/109/accept", json={"cargo_safety_acknowledged": True},
                )
                self.assertEqual(response.status_code, 403)
                self.db.query.assert_not_called()
                self.db.commit.assert_not_called()

    def test_http_rejects_non_boolean_confirmation(self):
        self._as_role(UserRole.driver)
        for value in ("true", "false", 1, 0, None):
            with self.subTest(value=value):
                response = self.client.put(
                    "/freights/109/accept", json={"cargo_safety_acknowledged": value},
                )
                self.assertEqual(response.status_code, 422)
                self.db.query.assert_not_called()

    def test_confirmation_cannot_smuggle_critical_fields(self):
        self._as_role(UserRole.driver)
        for field in ("client_id", "driver_id", "actual_vehicle_id", "final_price", "status"):
            with self.subTest(field=field):
                response = self.client.put(
                    "/freights/109/accept",
                    json={"cargo_safety_acknowledged": True, field: 1},
                )
                self.assertEqual(response.status_code, 422)
                self.db.query.assert_not_called()
                self.db.commit.assert_not_called()


if __name__ == "__main__":
    unittest.main()
