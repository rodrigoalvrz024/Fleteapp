import os
import unittest
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost/fleteapp_test",
)
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.models.driver import Driver, DriverStatus
from app.models.vehicle import Vehicle, VehicleType
from app.schemas.driver import DriverResponse
from app.services.driver_operational_service import (
    driver_operational_blockers,
    require_driver_can_operate,
)


class DriverOperationalRulesTests(unittest.TestCase):
    def _complete_driver(self) -> Driver:
        future = datetime.now(timezone.utc) + timedelta(days=60)
        driver = Driver(
            id=8,
            user_id=5,
            rut="12345678-9",
            license_number="B-123456",
            license_expiry=future,
            license_image_url="drivers/8/license.jpg",
            circulation_permit_url="drivers/8/permit.jpg",
            circulation_permit_expiry=future,
            technical_review_url="drivers/8/technical.jpg",
            technical_review_expiry=future,
            soap_url="drivers/8/soap.jpg",
            soap_expiry=future,
            status=DriverStatus.approved,
            is_available=False,
            rating_average=0,
            rating_count=0,
            total_trips=0,
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

    def test_complete_approved_driver_can_operate(self):
        driver = self._complete_driver()

        self.assertEqual(driver_operational_blockers(driver), [])
        require_driver_can_operate(driver)

        response = DriverResponse.model_validate(driver).model_dump()
        self.assertTrue(response["can_operate"])
        self.assertEqual(response["operational_blockers"], [])

    def test_expired_permit_blocks_driver(self):
        driver = self._complete_driver()
        driver.circulation_permit_expiry = datetime.now(timezone.utc) - timedelta(days=1)

        blockers = driver_operational_blockers(driver)

        self.assertIn("permiso de circulacion vencido", blockers)
        with self.assertRaises(HTTPException) as error:
            require_driver_can_operate(driver)
        self.assertEqual(error.exception.status_code, 403)
        self.assertIn("blockers", error.exception.detail)
        self.assertIn("permiso de circulacion vencido", error.exception.detail["blockers"])

        response = DriverResponse.model_validate(driver).model_dump()
        self.assertFalse(response["can_operate"])
        self.assertIn(
            "permiso de circulacion vencido",
            response["operational_blockers"],
        )

    def test_missing_vehicle_blocks_driver(self):
        driver = self._complete_driver()
        driver.vehicle = None

        blockers = driver_operational_blockers(driver)

        self.assertIn("Falta vehiculo", blockers)


if __name__ == "__main__":
    unittest.main()
