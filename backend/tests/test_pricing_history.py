import os
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")
os.environ.setdefault("DATABASE_URL", "postgresql://postgres:postgres@localhost/muvv_test")
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.services.freight_service import estimate_price, normalize_service_type, recommend_vehicle_type
from app.services.pricing_history_service import record_pricing_snapshot


class PricingHistoryTests(unittest.TestCase):
    def _freight(self):
        started_at = datetime(2026, 8, 12, 12, 0, tzinfo=timezone.utc)
        vehicle = SimpleNamespace(
            id=44,
            type=SimpleNamespace(value="van"),
            brand="Mercedes",
            model="Sprinter",
            year=2024,
            max_weight_kg=1400,
            max_volume_m3=10,
        )
        return SimpleNamespace(
            id=22,
            estimated_price=55_300.0,
            client_pays=55_300.0,
            final_price=None,
            driver_receives=47_700.0,
            platform_fee=7_600.0,
            helpers_cost=10_000.0,
            distance_km=12.4,
            actual_distance_km=None,
            estimated_duration_minutes=31.0,
            recommended_vehicle_type="van",
            selected_vehicle_type="van",
            pricing_version="v2",
            pricing_type="automatic",
            service_type="moving",
            cargo_weight_kg=650.0,
            cargo_volume_m3=4.5,
            requires_helpers=1,
            extra_stops=1,
            is_urgent=False,
            origin_address="Av. Apoquindo 4501, Las Condes, Santiago",
            destination_address="Av. Providencia 1208, Providencia, Santiago",
            requested_at=started_at - timedelta(minutes=20),
            price_estimated_at=started_at - timedelta(minutes=19),
            customer_confirmed_at=started_at - timedelta(minutes=18),
            driver_assigned_at=started_at - timedelta(minutes=10),
            driver_accepted_at=started_at - timedelta(minutes=10),
            driver_arrived_pickup_at=started_at - timedelta(minutes=2),
            trip_started_at=started_at,
            trip_completed_at=None,
            started_at=started_at,
            completed_at=None,
            driver_arrived_destination_at=None,
            cancelled_at=None,
            driver=SimpleNamespace(vehicle=vehicle),
        )

    def _price(self):
        return estimate_price(
            12.4,
            650,
            helpers=1,
            duration_minutes=31,
            volume_m3=4.5,
            service_type="moving",
            extra_stops=1,
        )

    def test_estimate_exposes_a_reproducible_breakdown(self):
        price = self._price()

        self.assertEqual(price["pricing_version"], "v2")
        self.assertGreater(price["distance_charge"], 0)
        self.assertGreater(price["time_charge"], 0)
        self.assertEqual(price["helper_charge"], 10_000)
        self.assertEqual(price["extra_stops_charge"], 2_500)
        self.assertEqual(price["customer_price"], price["client_pays"])
        self.assertEqual(
            price["platform_fee"],
            price["customer_price"] - price["driver_earnings"],
        )

    def test_snapshot_keeps_original_estimate_and_vehicle_details(self):
        freight = self._freight()
        db = MagicMock()
        snapshot = record_pricing_snapshot(
            db, freight, snapshot_type="customer_confirmed", pricing_components=self._price()
        )

        self.assertEqual(snapshot.freight_id, 22)
        self.assertEqual(snapshot.estimated_customer_price, 55_300.0)
        self.assertEqual(snapshot.pricing_version, "v2")
        self.assertEqual(snapshot.service_type, "moving")
        self.assertEqual(snapshot.pickup_commune, "Las Condes")
        self.assertEqual(snapshot.dropoff_commune, "Providencia")
        self.assertEqual(snapshot.actual_vehicle_id, 44)
        self.assertEqual(snapshot.actual_vehicle_type, "van")
        self.assertEqual(snapshot.extra_stops_count, 1)
        db.add.assert_called_once_with(snapshot)

    def test_final_snapshot_does_not_mutate_the_confirmed_snapshot(self):
        freight = self._freight()
        db = MagicMock()
        original = record_pricing_snapshot(
            db, freight, snapshot_type="customer_confirmed", pricing_components=self._price()
        )
        freight.final_price = 57_500.0
        freight.actual_distance_km = 13.1
        freight.trip_completed_at = freight.trip_started_at + timedelta(minutes=42)
        freight.completed_at = freight.trip_completed_at

        completed = record_pricing_snapshot(db, freight, snapshot_type="trip_completed")

        self.assertEqual(original.estimated_customer_price, 55_300.0)
        self.assertIsNone(original.final_customer_price)
        self.assertEqual(completed.final_customer_price, 57_500.0)
        self.assertEqual(completed.price_adjustment_amount, 2_200.0)
        self.assertEqual(completed.actual_distance_km, 13.1)
        self.assertEqual(completed.actual_duration_minutes, 42.0)

    def test_original_snapshot_keeps_formula_when_policy_changes_later(self):
        freight = self._freight()
        db = MagicMock()
        original_price = self._price()
        original = record_pricing_snapshot(
            db, freight, snapshot_type="customer_confirmed", pricing_components=original_price
        )
        later = estimate_price(
            12.4,
            650,
            helpers=2,
            duration_minutes=31,
            volume_m3=4.5,
            service_type="moving",
            extra_stops=1,
        )

        self.assertNotEqual(
            original.calculation_metadata["helper_charge"], later["helper_charge"]
        )
        self.assertEqual(original.pricing_version, "v2")

    def test_normalizes_service_types_and_recommends_a_vehicle(self):
        self.assertEqual(normalize_service_type("Paqueteria"), "package")
        self.assertEqual(normalize_service_type("Hogar u oficina"), "home_office")
        self.assertEqual(recommend_vehicle_type(300), "pickup")
        self.assertEqual(recommend_vehicle_type(800), "van")
        self.assertEqual(recommend_vehicle_type(2_500), "truck_medium")


if __name__ == "__main__":
    unittest.main()
