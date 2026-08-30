import unittest
from types import SimpleNamespace

from app.models.vehicle import Vehicle, VehicleApprovalStatus, VehicleType
from app.schemas.feedback import TripFeedbackCreate
from app.services.freight_matching_service import (
    compatible_vehicles,
    driver_matches_freight,
    vehicle_supports_freight,
)


def _vehicle(
    vehicle_type: VehicleType,
    *,
    status: str = VehicleApprovalStatus.approved.value,
    weight: float = 1000,
    volume: float = 8,
    services: list[str] | None = None,
) -> Vehicle:
    return Vehicle(
        driver_id=1,
        type=vehicle_type,
        brand="Prueba",
        model="Unidad",
        year=2024,
        plate=f"TEST{vehicle_type.value[:2].upper()}{weight:g}",
        color="Blanco",
        max_weight_kg=weight,
        max_volume_m3=volume,
        approval_status=status,
        supported_service_types=services or [],
    )


class FreightMatchingTest(unittest.TestCase):
    def setUp(self):
        self.moving = SimpleNamespace(
            service_type="moving",
            selected_vehicle_type="van",
            recommended_vehicle_type="van",
            cargo_weight_kg=350,
            cargo_volume_m3=4,
        )

    def test_moving_rejects_pickup_and_accepts_approved_van(self):
        pickup = _vehicle(VehicleType.pickup, weight=900, volume=6)
        van = _vehicle(VehicleType.van, weight=900, volume=9)

        self.assertFalse(vehicle_supports_freight(pickup, self.moving))
        self.assertTrue(vehicle_supports_freight(van, self.moving))

    def test_rejected_or_insufficient_vehicle_is_not_matched(self):
        rejected_van = _vehicle(
            VehicleType.van,
            status=VehicleApprovalStatus.rejected.value,
        )
        small_van = _vehicle(VehicleType.van, weight=300, volume=3)
        driver = SimpleNamespace(vehicles=[rejected_van, small_van])

        self.assertEqual(compatible_vehicles(driver, self.moving), [])
        self.assertFalse(driver_matches_freight(driver, self.moving))

    def test_only_registered_services_are_offered(self):
        restricted_van = _vehicle(
            VehicleType.van,
            services=["package", "urgent"],
        )
        self.assertFalse(vehicle_supports_freight(restricted_van, self.moving))


class TripFeedbackSchemaTest(unittest.TestCase):
    def test_accepts_exactly_five_scores_from_one_to_five(self):
        feedback = TripFeedbackCreate(
            overall_score=5,
            answers={
                "communication": 5,
                "punctuality": 4,
                "cargo_care": 5,
                "vehicle_condition": 4,
                "price_clarity": 5,
            },
        )
        self.assertEqual(feedback.overall_score, 5)

    def test_rejects_out_of_range_answer(self):
        with self.assertRaises(ValueError):
            TripFeedbackCreate(
                overall_score=5,
                answers={
                    "communication": 5,
                    "punctuality": 4,
                    "cargo_care": 0,
                    "vehicle_condition": 4,
                    "price_clarity": 5,
                },
            )


if __name__ == "__main__":
    unittest.main()
