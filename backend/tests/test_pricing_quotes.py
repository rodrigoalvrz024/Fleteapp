import os
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")
os.environ.setdefault("DATABASE_URL", "postgresql://postgres:postgres@localhost/muvv_test")
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from fastapi import HTTPException

from app.services.pricing_quote_service import (
    consume_pricing_quote,
    create_pricing_quote,
    quote_input_fingerprint,
)


class PricingQuoteTests(unittest.TestCase):
    def _data(self, **changes):
        data = {
            "origin_lat": -33.44,
            "origin_lng": -70.65,
            "destination_lat": -33.42,
            "destination_lng": -70.61,
            "cargo_description": "Cajas de ropa",
            "cargo_weight_kg": 80,
            "cargo_volume_m3": 1.2,
            "requires_helpers": 1,
            "extra_stops": 0,
            "pickup_floor": None,
            "delivery_floor": None,
            "pickup_has_elevator": True,
            "delivery_has_elevator": True,
            "service_type": "home_office",
            "is_urgent": False,
            "scheduled_at": None,
            "requested_vehicle_type": None,
        }
        data.update(changes)
        return SimpleNamespace(**data)

    def _price(self):
        return {
            "pricing_version": "v2",
            "pricing_type": "automatic",
            "requires_manual_quote": False,
            "recommended_vehicle_type": "pickup",
            "selected_vehicle_type": "pickup",
            "customer_price": 22_100,
        }

    def _route(self):
        return {
            "distance_km": 4.2,
            "duration_minutes": 14.0,
            "provider": "google_routes",
            "calculated_at": datetime.now(timezone.utc),
        }

    def _mock_db_for(self, quote):
        db = MagicMock()
        db.query.return_value.filter.return_value.with_for_update.return_value.first.return_value = quote
        return db

    def test_quote_binds_to_the_same_input_and_expires(self):
        data = self._data()
        db = MagicMock()
        quote = create_pricing_quote(
            db,
            client_id=7,
            data=data,
            route=self._route(),
            pricing=self._price(),
        )

        self.assertEqual(quote.client_id, 7)
        self.assertEqual(quote.pricing_version, "v2")
        self.assertEqual(quote.request_fingerprint, quote_input_fingerprint(data))
        self.assertGreater(quote.expires_at, datetime.now(timezone.utc))
        db.add.assert_called_once_with(quote)

    def test_quote_cannot_be_reused_or_changed(self):
        data = self._data()
        quote = SimpleNamespace(
            id="quote-id",
            client_id=7,
            used_at=None,
            expires_at=datetime.now(timezone.utc) + timedelta(minutes=2),
            request_fingerprint=quote_input_fingerprint(data),
        )
        returned = consume_pricing_quote(
            self._mock_db_for(quote), quote_id="quote-id", client_id=7, data=data
        )
        self.assertIs(returned, quote)

        with self.assertRaises(HTTPException) as error:
            consume_pricing_quote(
                self._mock_db_for(quote),
                quote_id="quote-id",
                client_id=7,
                data=self._data(cargo_weight_kg=90),
            )
        self.assertEqual(error.exception.status_code, 409)

    def test_expired_or_used_quote_is_rejected(self):
        data = self._data()
        for expires_at, used_at in (
            (datetime.now(timezone.utc) - timedelta(seconds=1), None),
            (datetime.now(timezone.utc) + timedelta(minutes=1), datetime.now(timezone.utc)),
        ):
            quote = SimpleNamespace(
                id="quote-id",
                client_id=7,
                used_at=used_at,
                expires_at=expires_at,
                request_fingerprint=quote_input_fingerprint(data),
            )
            with self.subTest(expires_at=expires_at, used_at=used_at):
                with self.assertRaises(HTTPException) as error:
                    consume_pricing_quote(
                        self._mock_db_for(quote),
                        quote_id="quote-id",
                        client_id=7,
                        data=data,
                    )
                self.assertEqual(error.exception.status_code, 409)


if __name__ == "__main__":
    unittest.main()
