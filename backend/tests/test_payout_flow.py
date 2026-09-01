import os
import unittest

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")
from unittest.mock import MagicMock

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost/muvv_test",
)
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.models.driver_payout import DriverPayout, DriverPayoutStatus
from app.models.freight import FreightRequest, FreightStatus
from app.models.payment import Payment, PaymentStatus
from app.routers.payouts import VALID_TRANSITIONS
from app.services.payout_service import ensure_driver_payout


class DriverPayoutFlowTests(unittest.TestCase):
    def _authorized_payment(self) -> Payment:
        freight = FreightRequest(
            id=9,
            driver_id=3,
            driver_receives=27800,
            status=FreightStatus.completed,
        )
        payment = Payment(
            id=4,
            freight_id=freight.id,
            status=PaymentStatus.authorized,
        )
        payment.freight = freight
        return payment

    def test_authorized_payment_creates_pending_payout(self):
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = None

        payout = ensure_driver_payout(db, self._authorized_payment())

        self.assertIsInstance(payout, DriverPayout)
        self.assertEqual(payout.freight_id, 9)
        self.assertEqual(payout.driver_id, 3)
        self.assertEqual(payout.amount, 27800)
        self.assertEqual(payout.status, DriverPayoutStatus.pending)
        db.add.assert_called_once_with(payout)
        db.flush.assert_called_once()

    def test_authorized_payment_does_not_duplicate_existing_payout(self):
        existing = DriverPayout(id=12, status=DriverPayoutStatus.pending)
        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = existing

        payout = ensure_driver_payout(db, self._authorized_payment())

        self.assertIs(payout, existing)
        db.add.assert_not_called()

    def test_authorized_payment_waits_until_delivery_is_completed(self):
        db = MagicMock()
        payment = self._authorized_payment()
        payment.freight.status = FreightStatus.in_progress

        payout = ensure_driver_payout(db, payment)

        self.assertIsNone(payout)
        db.query.assert_not_called()
        db.add.assert_not_called()

    def test_paid_payout_is_final(self):
        self.assertEqual(VALID_TRANSITIONS[DriverPayoutStatus.paid], set())
        self.assertIn(
            DriverPayoutStatus.paid,
            VALID_TRANSITIONS[DriverPayoutStatus.pending],
        )


if __name__ == "__main__":
    unittest.main()
