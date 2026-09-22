import asyncio
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, patch

from tests.test_pricing_service import PricingService  # isolated test environment
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from fastapi import HTTPException

from app.database import Base
from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest, FreightStatus
from app.models.freight_driver_decline import FreightDriverDecline
from app.models.payment import Payment, PaymentMethod, PaymentStatus
from app.models.user import User, UserRole
from app.models.vehicle import Vehicle, VehicleApprovalStatus, VehicleType
from app.routers.freights import accept_freight, list_freights, _require_freight_view_access
from app.services.freight_dispatch_service import (
    driver_can_receive_offer, freight_is_open_offer, schedule_conflicts,
)
from app.services.notification_service import send_notification_to_drivers


class FreightDispatchTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine("sqlite://")
        Base.metadata.create_all(self.engine)
        self.db = Session(self.engine)
        self.addCleanup(self.engine.dispose)
        self.addCleanup(self.db.close)
        self.now = datetime.now(timezone.utc)
        self.client = self.user(1, UserRole.client)
        self.driver_user = self.user(2, UserRole.driver)
        expiry = self.now + timedelta(days=365)
        self.driver = Driver(
            id=1, user_id=2, rut="test-driver", status=DriverStatus.approved,
            is_available=True, license_number="test", license_image_url="private/license",
            license_expiry=expiry, circulation_permit_url="private/permit",
            circulation_permit_expiry=expiry, technical_review_url="private/review",
            technical_review_expiry=expiry, soap_url="private/soap", soap_expiry=expiry,
        )
        self.vehicle = Vehicle(
            id=1, driver_id=1, type=VehicleType.truck_medium, brand="Test",
            model="Test", year=2025, plate="TEST01", color="White",
            max_weight_kg=4000, max_volume_m3=20,
            approval_status=VehicleApprovalStatus.approved.value,
        )
        self.db.add_all([self.driver, self.vehicle])
        self.freight = self.offer(1)
        self.db.commit()

    def user(self, identifier, role):
        user = User(id=identifier, email=f"test{identifier}@example.invalid",
                    phone=f"test{identifier}", full_name="Test", hashed_password="test-hash",
                    role=role, fcm_token=f"test-token-{identifier}")
        self.db.add(user)
        return user

    def offer(self, identifier, **changes):
        fields = dict(
            id=identifier, client_id=1, status=FreightStatus.pending,
            origin_address="Test origin", origin_lat=-33.4, origin_lng=-70.6,
            destination_address="Test destination", destination_lat=-33.5,
            destination_lng=-70.7, cargo_description="Test boxes", cargo_weight_kg=40,
            cargo_volume_m3=1, service_type="package", is_urgent=False,
            scheduled_at=self.now + timedelta(days=1), estimated_duration_minutes=30,
        )
        freight = FreightRequest(**(fields | changes))
        freight.payment = Payment(amount=20000, method=PaymentMethod.webpay,
                                  status=PaymentStatus.authorized)
        self.db.add(freight)
        self.db.flush()
        return freight

    def send(self):
        with patch("app.services.notification_service.send_push_notification", new_callable=AsyncMock) as push:
            push.return_value = "test-message"
            sent = asyncio.run(send_notification_to_drivers(
                self.db, "Test", "Test", freight=self.freight))
            return sent, push.call_count

    def test_eligible_driver_receives_offer(self):
        self.assertTrue(driver_can_receive_offer(self.db, self.driver, self.freight))
        self.assertEqual(self.send(), (1, 1))

    def test_refunded_cancelled_assigned_or_deleted_offer_is_not_sent(self):
        for field, value in [("status", FreightStatus.cancelled), ("driver_id", 1),
                             ("deleted_at", self.now)]:
            with self.subTest(field=field):
                previous = getattr(self.freight, field)
                setattr(self.freight, field, value)
                self.db.commit()
                self.assertFalse(freight_is_open_offer(self.freight))
                self.assertEqual(self.send(), (0, 0))
                setattr(self.freight, field, previous)
                self.db.commit()
        self.freight.payment.status = PaymentStatus.pending
        self.db.commit()
        self.assertEqual(self.send(), (0, 0))

    def test_ineligible_driver_is_not_notified(self):
        for field, value in [("license_expiry", self.now - timedelta(days=1)),
                             ("soap_url", None), ("is_available", False),
                             ("status", DriverStatus.suspended), ("deleted_at", self.now)]:
            with self.subTest(field=field):
                previous = getattr(self.driver, field)
                setattr(self.driver, field, value)
                self.db.commit()
                self.assertEqual(self.send(), (0, 0))
                setattr(self.driver, field, previous)
                self.db.commit()

    def test_inactive_user_and_incompatible_vehicle_are_not_notified(self):
        self.driver_user.is_active = False
        self.db.commit()
        self.assertEqual(self.send(), (0, 0))
        self.driver_user.is_active = True
        self.vehicle.max_weight_kg = 1
        self.db.commit()
        self.assertEqual(self.send(), (0, 0))

    def test_rejected_offer_is_not_redispatched(self):
        self.db.add(FreightDriverDecline(driver_id=1, freight_id=1))
        self.db.commit()
        self.assertEqual(self.send(), (0, 0))
        self.assertEqual(list_freights("available", self.db, self.driver_user), [])

    def test_overlapping_assignment_blocks_list_detail_push_and_accept(self):
        self.offer(2, status=FreightStatus.accepted, driver_id=1)
        self.db.commit()
        self.assertEqual(list_freights("available", self.db, self.driver_user), [])
        self.assertEqual(self.send(), (0, 0))
        with self.assertRaises(HTTPException) as detail:
            _require_freight_view_access(self.freight, self.db, self.driver_user)
        self.assertEqual(detail.exception.status_code, 409)
        # SQLite exercises endpoint logic, not PostgreSQL lock semantics.
        with patch("app.routers.freights.lock_first", side_effect=lambda q: q.first()) as lock:
            with self.assertRaises(HTTPException) as accept:
                accept_freight(1, None, self.db, self.driver_user)
            self.assertEqual(accept.exception.status_code, 409)
            self.assertEqual(lock.call_count, 2)
        self.assertIsNone(self.freight.driver_id)

    def test_non_overlapping_future_assignment_remains_available(self):
        self.offer(2, status=FreightStatus.accepted, driver_id=1,
                   scheduled_at=self.now + timedelta(days=2))
        self.db.commit()
        self.assertEqual([f.id for f in list_freights("available", self.db, self.driver_user)], [1])
        self.assertEqual(self.send(), (1, 1))

    def test_completed_and_cancelled_assignments_do_not_block(self):
        for identifier, status in [(2, FreightStatus.completed), (3, FreightStatus.cancelled)]:
            self.offer(identifier, status=status, driver_id=1)
        self.db.commit()
        self.assertEqual(self.send(), (1, 1))

    def test_current_owner_and_admin_keep_access_when_offers_are_hidden(self):
        self.offer(2, status=FreightStatus.accepted, driver_id=1)
        admin = self.user(3, UserRole.admin)
        stranger = self.user(4, UserRole.client)
        self.db.commit()
        for user in (self.client, admin):
            _require_freight_view_access(self.freight, self.db, user)
        with self.assertRaises(HTTPException) as error:
            _require_freight_view_access(self.freight, self.db, stranger)
        self.assertEqual(error.exception.status_code, 403)

    def test_safe_margins_and_boundary(self):
        assigned = self.offer(2, status=FreightStatus.accepted, driver_id=1)
        for delta, expected in [(89, True), (90, False)]:
            self.freight.scheduled_at = assigned.scheduled_at + timedelta(minutes=delta)
            self.assertEqual(schedule_conflicts(self.freight, [assigned], now=self.now), expected)
        assigned.service_type = "moving"
        self.assertTrue(schedule_conflicts(self.freight, [assigned], now=self.now))
        self.freight.scheduled_at = assigned.scheduled_at + timedelta(minutes=210)
        self.assertFalse(schedule_conflicts(self.freight, [assigned], now=self.now))

    def test_missing_duration_overdue_or_in_progress_blocks_additional_booking(self):
        assigned = self.offer(2, status=FreightStatus.accepted, driver_id=1,
                              scheduled_at=self.now + timedelta(days=2))
        for field, value in [("estimated_duration_minutes", None),
                             ("scheduled_at", self.now - timedelta(minutes=1)),
                             ("status", FreightStatus.in_progress), ("is_urgent", True)]:
            previous = getattr(assigned, field)
            setattr(assigned, field, value)
            self.assertTrue(schedule_conflicts(self.freight, [assigned], now=self.now))
            setattr(assigned, field, previous)
        self.freight.estimated_duration_minutes = None
        self.assertTrue(schedule_conflicts(self.freight, [assigned], now=self.now))
        self.assertFalse(schedule_conflicts(self.freight, [], now=self.now))

    def test_timezone_offsets_represent_same_booking(self):
        assigned = self.offer(2, status=FreightStatus.accepted, driver_id=1)
        self.freight.scheduled_at = assigned.scheduled_at.astimezone(timezone(timedelta(hours=-3)))
        self.assertTrue(schedule_conflicts(self.freight, [assigned], now=self.now))


if __name__ == "__main__":
    unittest.main()
