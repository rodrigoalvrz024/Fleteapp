import os
import unittest
from decimal import Decimal

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")
os.environ.setdefault("DATABASE_URL", "postgresql://postgres:postgres@localhost/muvv_test")
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.services.pricing_service import (
    PricingInputError,
    PricingPolicy,
    PricingService,
)


class PricingServiceTests(unittest.TestCase):
    def setUp(self):
        self.service = PricingService()

    def estimate(self, **changes):
        values = {
            "distance_km": 8,
            "duration_minutes": 20,
            "weight_kg": 120,
            "volume_m3": 1,
            "service_type": "home_office",
            "cargo_description": "Cajas y silla",
        }
        values.update(changes)
        return self.service.estimate(**values)

    def test_short_route_uses_vehicle_minimum_and_consistent_rounding(self):
        price = self.estimate(distance_km=1, duration_minutes=2, weight_kg=10)

        self.assertEqual(price["selected_vehicle_type"], "pickup")
        self.assertTrue(price["minimum_applied"])
        self.assertEqual(price["base_price"] % 100, 0)
        self.assertEqual(price["customer_price"] % 100, 0)

    def test_longer_or_heavier_cargo_recommends_larger_vehicle(self):
        price = self.estimate(weight_kg=700, volume_m3=4)

        self.assertEqual(price["recommended_vehicle_type"], "van")
        self.assertEqual(price["recommended_vehicle_name"], "Furgon")
        self.assertGreater(price["distance_charge"], 0)
        self.assertGreater(price["time_charge"], 0)

    def test_helpers_stops_and_urgency_are_explicit(self):
        normal = self.estimate()
        urgent = self.estimate(helpers=2, extra_stops=2, is_urgent=True)

        self.assertEqual(urgent["helper_charge"], 20_000)
        self.assertEqual(urgent["extra_stops_charge"], 5_000)
        self.assertGreater(urgent["urgency_charge"], 0)
        self.assertGreater(urgent["customer_price"], normal["customer_price"])

    def test_pickup_cannot_be_selected_when_van_is_required(self):
        with self.assertRaises(PricingInputError):
            self.estimate(weight_kg=800, requested_vehicle_type="pickup")

    def test_moving_requires_a_medium_truck_and_has_a_50k_floor(self):
        price = self.estimate(
            distance_km=1,
            duration_minutes=3,
            weight_kg=25,
            volume_m3=0.5,
            service_type="moving",
            cargo_description="Cajas de mudanza",
        )

        self.assertEqual(price["recommended_vehicle_type"], "truck_medium")
        self.assertEqual(price["selected_vehicle_type"], "truck_medium")
        self.assertGreaterEqual(price["base_price"], 50_000)
        self.assertEqual(
            price["calculation_metadata"]["service_minimum_fare"], 50_000
        )

    def test_moving_rejects_a_smaller_requested_vehicle(self):
        with self.assertRaises(PricingInputError):
            self.estimate(
                service_type="moving",
                cargo_description="Cajas de mudanza",
                requested_vehicle_type="van",
            )

    def test_cargo_above_supported_capacity_requires_manual_quote(self):
        price = self.estimate(weight_kg=11_000, volume_m3=55)

        self.assertTrue(price["requires_manual_quote"])
        self.assertEqual(price["pricing_type"], "manual_quote")
        self.assertEqual(price["manual_quote_reason"], "cargo_outside_supported_capacity")

    def test_special_cargo_requires_manual_quote_without_inventing_a_price(self):
        price = self.estimate(cargo_description="Piano de cola para segundo piso")

        self.assertTrue(price["requires_manual_quote"])
        self.assertNotIn("customer_price", price)

    def test_customer_driver_and_platform_amounts_reconcile(self):
        price = self.estimate(helpers=1, extra_stops=1)

        self.assertEqual(
            price["platform_fee"],
            price["customer_price"] - price["driver_earnings"],
        )
        self.assertEqual(price["driver_earnings"], price["driver_receives"])

    def test_policy_can_be_recalibrated_without_changing_the_formula(self):
        service = PricingService(
            policy=PricingPolicy(
                helper_fee=12_000,
                urgency_multiplier=Decimal("1.20"),
                rounding_increment=500,
            )
        )
        price = service.estimate(
            distance_km=8,
            duration_minutes=20,
            weight_kg=120,
            helpers=1,
            is_urgent=True,
        )

        self.assertEqual(price["helper_charge"], 12_000)
        self.assertEqual(price["customer_price"] % 500, 0)


if __name__ == "__main__":
    unittest.main()
