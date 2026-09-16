import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

# Reuse the isolated test configuration before importing API dependencies.
from tests.test_pricing_service import PricingService
from tests.test_matching_and_feedback import _vehicle
from fastapi import HTTPException
from pydantic import ValidationError
from app.models.driver import DriverStatus
from app.models.freight import FreightRequest
from app.models.payment import PaymentStatus
from app.models.vehicle import VehicleType
from app.routers.freights import accept_freight
from app.schemas.freight import FreightAcceptRequest
from app.services.freight_matching_service import (
    default_service_types,
    vehicle_supports_freight,
    requires_cargo_safety_acknowledgement,
)


class PickupCargoSafetyTests(unittest.TestCase):
    def setUp(self):
        self.freight = SimpleNamespace(
            id=109, service_type="home_office", selected_vehicle_type="pickup",
            recommended_vehicle_type="pickup", cargo_weight_kg=80,
            cargo_volume_m3=0.6, payment=SimpleNamespace(status=PaymentStatus.authorized),
        )
        self.vehicle = _vehicle(VehicleType.pickup, weight=500, volume=2)
        self.vehicle.id = 10

    def test_recommended_pickup_matches_small_home_office_cargo(self):
        quote = PricingService().estimate(
            distance_km=2.2, duration_minutes=7, weight_kg=80, volume_m3=0.6,
            service_type="home_office", cargo_description="Lavadora de prueba",
        )
        self.assertEqual(quote["selected_vehicle_type"], "pickup")
        self.assertEqual(quote["customer_price"], 21500)
        self.assertIn("home_office", default_service_types("pickup"))
        self.assertTrue(vehicle_supports_freight(self.vehicle, self.freight))

    def test_existing_explicit_service_restrictions_remain_in_force(self):
        self.vehicle.supported_service_types = ["package", "urgent"]
        self.assertFalse(vehicle_supports_freight(self.vehicle, self.freight))

    def test_capacity_approval_and_required_vehicle_are_not_bypassed(self):
        for changes in (
            {"max_weight_kg": 50}, {"max_volume_m3": 0.3},
            {"approval_status": "pending"}, {"approval_status": "rejected"},
            {"deleted_at": "deleted"},
        ):
            with self.subTest(changes=changes):
                vehicle = _vehicle(VehicleType.pickup, weight=500, volume=2)
                for key, value in changes.items():
                    setattr(vehicle, key, value)
                self.assertFalse(vehicle_supports_freight(vehicle, self.freight))
        for required in ("van", "truck_small", "truck_medium", "truck_large"):
            self.freight.selected_vehicle_type = required
            self.assertFalse(vehicle_supports_freight(self.vehicle, self.freight))

    def test_moving_still_rejects_pickup(self):
        self.freight.service_type = "moving"
        self.assertFalse(vehicle_supports_freight(self.vehicle, self.freight))

    def test_every_offered_vehicle_matches_the_same_service_and_capacity(self):
        for service in ("package", "urgent", "home_office", "moving"):
            for kind in VehicleType:
                if service == "moving" and kind.value not in ("truck_medium", "truck_large"):
                    continue
                with self.subTest(service=service, vehicle=kind.value):
                    quote = PricingService().estimate(
                        distance_km=2.2, duration_minutes=7, weight_kg=80,
                        volume_m3=0.6, service_type=service,
                        requested_vehicle_type=kind.value,
                    )
                    freight = SimpleNamespace(
                        service_type=service, selected_vehicle_type=quote["selected_vehicle_type"],
                        recommended_vehicle_type=quote["recommended_vehicle_type"],
                        cargo_weight_kg=80, cargo_volume_m3=0.6,
                    )
                    self.assertTrue(vehicle_supports_freight(_vehicle(kind), freight))

    def test_warning_is_required_only_for_home_office_with_actual_pickup(self):
        self.assertTrue(requires_cargo_safety_acknowledgement(self.vehicle, self.freight))
        van = _vehicle(VehicleType.van)
        self.assertFalse(requires_cargo_safety_acknowledgement(van, self.freight))
        self.freight.service_type = "package"
        self.assertFalse(requires_cargo_safety_acknowledgement(self.vehicle, self.freight))

    def test_acknowledgement_is_a_strict_boolean_defaulting_to_false(self):
        self.assertFalse(FreightAcceptRequest().cargo_safety_acknowledged)
        for invalid in ("true", "false", 1, 0, None):
            with self.subTest(value=invalid), self.assertRaises(ValidationError):
                FreightAcceptRequest(cargo_safety_acknowledged=invalid)

    def _db(self):
        driver = SimpleNamespace(id=7, status=DriverStatus.approved, vehicles=[self.vehicle])
        queries = [MagicMock() for _ in range(5)]
        for query in queries:
            query.filter.return_value = query
        queries[0].first.return_value = driver
        queries[1].first.return_value = self.freight
        queries[2].first.return_value = None
        def assign_vehicle(values, **_kwargs):
            self.freight.actual_vehicle_id = values[FreightRequest.actual_vehicle_id]
            return 1

        queries[3].update.side_effect = assign_vehicle
        queries[4].first.return_value = self.freight
        db = MagicMock()
        db.query.side_effect = queries
        return db, queries

    @patch("app.routers.freights.require_driver_can_operate")
    def test_old_client_or_declined_warning_cannot_assign_freight(self, _operate):
        for data in (None, FreightAcceptRequest(), FreightAcceptRequest(vehicle_id=10)):
            with self.subTest(data=data):
                db, queries = self._db()
                with self.assertRaises(HTTPException) as error:
                    accept_freight(109, data, db, SimpleNamespace(id=2))
                self.assertEqual(error.exception.status_code, 409)
                for query in queries:
                    query.update.assert_not_called()
                db.commit.assert_not_called()

    @patch("app.routers.freights.record_pricing_snapshot")
    @patch("app.routers.freights.record_audit_event")
    @patch("app.routers.freights.require_driver_can_operate")
    def test_confirmed_notice_allows_assignment_and_is_audited(self, _operate, audit, _snapshot):
        db, queries = self._db()
        result = accept_freight(
            109, FreightAcceptRequest(cargo_safety_acknowledged=True),
            db, SimpleNamespace(id=2),
        )
        self.assertIs(result, self.freight)
        queries[3].update.assert_called_once()
        db.commit.assert_called_once()
        event = audit.call_args_list[0].kwargs
        self.assertEqual(event["event_type"], "freight.accepted")
        self.assertTrue(event["metadata"]["cargo_safety_acknowledged"])
        self.assertEqual(event["metadata"]["cargo_safety_notice_version"], "pickup_home_office_v1")

    @patch("app.routers.freights.record_pricing_snapshot")
    @patch("app.routers.freights.record_audit_event")
    @patch("app.routers.freights.require_driver_can_operate")
    def test_other_acceptance_cases_remain_backward_compatible(self, _operate, _audit, _snapshot):
        for kind, service in ((VehicleType.van, "home_office"), (VehicleType.pickup, "package")):
            with self.subTest(vehicle=kind, service=service):
                self.setUp()
                self.vehicle.type = kind
                self.freight.service_type = service
                db, _queries = self._db()
                accept_freight(109, None, db, SimpleNamespace(id=2))
                db.commit.assert_called_once()

    @patch("app.routers.freights.require_driver_can_operate")
    def test_acknowledgement_does_not_bypass_vehicle_or_payment_restrictions(self, _operate):
        for invalid in ("vehicle", "payment"):
            with self.subTest(invalid=invalid):
                self.setUp()
                if invalid == "vehicle":
                    self.vehicle.approval_status = "rejected"
                else:
                    self.freight.payment.status = PaymentStatus.pending
                db, queries = self._db()
                with self.assertRaises(HTTPException):
                    accept_freight(
                        109, FreightAcceptRequest(cargo_safety_acknowledged=True),
                        db, SimpleNamespace(id=2),
                    )
                db.commit.assert_not_called()
                for query in queries:
                    query.update.assert_not_called()

    @patch("app.routers.freights.require_driver_can_operate")
    def test_confirmation_cannot_select_another_drivers_vehicle(self, _operate):
        db, queries = self._db()
        with self.assertRaises(HTTPException) as error:
            accept_freight(
                109, FreightAcceptRequest(vehicle_id=999, cargo_safety_acknowledged=True),
                db, SimpleNamespace(id=2),
            )
        self.assertEqual(error.exception.status_code, 403)
        db.commit.assert_not_called()
        for query in queries:
            query.update.assert_not_called()

    @patch("app.routers.freights.record_pricing_snapshot")
    @patch("app.routers.freights.record_audit_event")
    @patch("app.routers.freights.require_driver_can_operate")
    def test_legacy_app_can_still_accept_with_a_compatible_van(self, _operate, audit, _snapshot):
        db, queries = self._db()
        van = _vehicle(VehicleType.van, weight=900, volume=5)
        van.id = 11
        queries[0].first.return_value.vehicles.append(van)
        accept_freight(109, None, db, SimpleNamespace(id=2))
        event = audit.call_args_list[0].kwargs
        self.assertEqual(event["after_data"]["actual_vehicle_id"], van.id)
        self.assertEqual(self.freight.actual_vehicle_id, van.id)
        self.assertFalse(event["metadata"]["cargo_safety_acknowledged"])
        self.assertIsNone(event["metadata"]["cargo_safety_notice_version"])
        db.commit.assert_called_once()

    @patch("app.routers.freights.require_driver_can_operate")
    def test_explicit_pickup_still_requires_notice_when_a_van_exists(self, _operate):
        db, queries = self._db()
        van = _vehicle(VehicleType.van, weight=900, volume=5)
        van.id = 11
        queries[0].first.return_value.vehicles.append(van)
        with self.assertRaises(HTTPException) as error:
            accept_freight(109, FreightAcceptRequest(vehicle_id=10), db, SimpleNamespace(id=2))
        self.assertEqual(error.exception.status_code, 409)
        db.commit.assert_not_called()
        for query in queries:
            query.update.assert_not_called()


if __name__ == "__main__":
    unittest.main()
