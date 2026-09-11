import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch


path = Path(__file__).resolve().parents[2] / "scripts" / "test-webpay-integration.py"
spec = importlib.util.spec_from_file_location("webpay_integration_runner", path)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class WebpayIntegrationRunnerTests(unittest.TestCase):
    def test_environment_never_inherits_merchant_or_database_credentials(self):
        with patch.dict("os.environ", {
            "TRANSBANK_ENVIRONMENT": "production",
            "TRANSBANK_API_KEY": "do-not-use",
            "TRANSBANK_COMMERCE_CODE": "do-not-use",
            "DATABASE_URL": "do-not-use",
            "SUPABASE_SERVICE_ROLE_KEY": "do-not-use",
            "HTTPS_PROXY": "do-not-use",
            "PYTHONPATH": "do-not-use",
            "SECRET_KEY": "do-not-use",
        }, clear=True):
            environment = runner.isolated_environment()
        self.assertEqual(environment["TRANSBANK_ENVIRONMENT"], "integration")
        self.assertEqual(environment["TRANSBANK_API_KEY"], "")
        self.assertEqual(environment["TRANSBANK_COMMERCE_CODE"], "")
        self.assertIn("127.0.0.1:1/", environment["DATABASE_URL"])
        self.assertNotIn("do-not-use", environment.values())
        self.assertNotIn("PYTHONPATH", environment)
        self.assertNotIn("HTTPS_PROXY", environment)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", environment)

    def test_approved_requires_matching_order_amount_status_and_code(self):
        result = SimpleNamespace(buy_order="synthetic", amount=1000,
                                 status="AUTHORIZED", response_code=0)
        self.assertEqual(runner.classify_result(result, "synthetic"), "approved")
        for field, value in (("amount", 1001), ("buy_order", "another"),
                             ("status", "FAILED"), ("response_code", -1)):
            changed = SimpleNamespace(**vars(result))
            setattr(changed, field, value)
            self.assertNotEqual(runner.classify_result(changed, "synthetic"), "approved")

    def test_declined_is_not_approved(self):
        result = SimpleNamespace(buy_order="synthetic", amount=1000,
                                 status="FAILED", response_code=-1)
        self.assertEqual(runner.classify_result(result, "synthetic"), "declined")

    def test_callback_rejects_duplicate_and_excess_fields(self):
        for data in ("token_ws=a&token_ws=b", "&".join(f"a{i}=x" for i in range(9))):
            with self.assertRaises(ValueError):
                runner.callback_fields(data)

    def test_callback_accepts_provider_form(self):
        self.assertEqual(runner.callback_fields("token_ws=synthetic-token"),
                         {"token_ws": "synthetic-token"})


if __name__ == "__main__":
    unittest.main()
