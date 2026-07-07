import os
import unittest

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost/fleteapp_test",
)
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.routers.users import _redact_user_audit_data


class SecurityHardeningTests(unittest.TestCase):
    def test_user_audit_redacts_fcm_token(self):
        data = {
            "full_name": "Conductor Demo",
            "fcm_token": "secret-device-token",
        }

        redacted = _redact_user_audit_data(data)

        self.assertEqual(redacted["full_name"], "Conductor Demo")
        self.assertEqual(redacted["fcm_token"], "[redacted]")
        self.assertEqual(data["fcm_token"], "secret-device-token")


if __name__ == "__main__":
    unittest.main()
