import os
import unittest

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")

os.environ.setdefault("DATABASE_URL", "postgresql://postgres:postgres@localhost/muvv_test")
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.services.maps_service import _autocomplete_suggestions


class PlacesServiceTests(unittest.TestCase):
    def test_autocomplete_response_is_reduced_to_safe_mobile_fields(self):
        suggestions = _autocomplete_suggestions(
            {
                "suggestions": [
                    {
                        "placePrediction": {
                            "place": "places/abc123",
                            "text": {"text": "Av. Providencia 1234, Providencia, Chile"},
                            "structuredFormat": {
                                "mainText": {"text": "Av. Providencia 1234"},
                                "secondaryText": {"text": "Providencia, Chile"},
                            },
                        }
                    }
                ]
            }
        )

        self.assertEqual(
            suggestions,
            [
                {
                    "place_id": "abc123",
                    "label": "Av. Providencia 1234",
                    "address": "Providencia, Chile",
                    "full_address": "Av. Providencia 1234, Providencia, Chile",
                }
            ],
        )

    def test_invalid_predictions_are_ignored(self):
        self.assertEqual(_autocomplete_suggestions({"suggestions": [{}]}), [])
