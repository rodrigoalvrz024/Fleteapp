"""Contract tests with synthetic responses; never contact a payment provider."""

import json
import os
import unittest
from unittest.mock import patch

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("SECRET_KEY", "synthetic-webpay-test-key-at-least-32-bytes")
os.environ.setdefault("DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:1/muvv_test")

import httpx
from fastapi import HTTPException

from app.core.config import settings
from app.services import transbank_service as webpay


REAL_CLIENT = httpx.Client
TOKEN = "synthetic-payment-token"
CREATE = {
    "buy_order": "fixture-order", "session_id": "fixture-session", "amount": 12000,
    "return_url": "https://example.com/payments/callback",
}
COMMIT = {
    "status": "AUTHORIZED", "response_code": 0, "buy_order": CREATE["buy_order"],
    "amount": 12000, "authorization_code": "123456", "accounting_date": "0910",
    "card_detail": {"card_number": "0000"},
}


class TransbankRestTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(settings, "TRANSBANK_ENVIRONMENT", "integration"))
        self.enterContext(patch.object(settings, "TRANSBANK_API_KEY", ""))
        self.enterContext(patch.object(settings, "TRANSBANK_COMMERCE_CODE", ""))
        self.requests = []
        self.clients = []
        self.response = httpx.Response(200, json=COMMIT)
        self.factory = self.enterContext(patch.object(webpay.httpx, "Client", side_effect=self.client))

    def client(self, **kwargs):
        def handler(request):
            self.requests.append(request)
            if isinstance(self.response, Exception):
                raise self.response
            return self.response

        client = REAL_CLIENT(transport=httpx.MockTransport(handler), **kwargs)
        self.clients.append(client)
        return client

    def tearDown(self):
        self.assertTrue(all(client.is_closed for client in self.clients))

    def deny(self, operation, status):
        with self.assertRaises(HTTPException) as error:
            operation()
        self.assertEqual(error.exception.status_code, status)
        self.assertNotIn(TOKEN, error.exception.detail)
        self.assertNotIn("synthetic-private-key", error.exception.detail)

    def test_create_uses_documented_endpoint_headers_and_json(self):
        self.response = httpx.Response(200, json={
            "token": TOKEN, "url": "https://webpay3gint.transbank.cl/webpayserver/initTransaction",
        })
        created = webpay.create_webpay_transaction(**CREATE)
        self.assertEqual(created.token, TOKEN)
        request = self.requests[0]
        self.assertEqual(request.method, "POST")
        self.assertEqual(str(request.url), webpay._HOSTS["integration"] + webpay._TRANSACTIONS_PATH)
        self.assertEqual(json.loads(request.content), CREATE)
        self.assertEqual(request.headers["Tbk-Api-Key-Id"], webpay._INTEGRATION_COMMERCE_CODE)
        self.assertEqual(request.headers["Tbk-Api-Key-Secret"], webpay._INTEGRATION_API_KEY)

    def test_commit_uses_put_without_body_and_preserves_result_contract(self):
        result = webpay.commit_webpay_transaction(TOKEN)
        request = self.requests[0]
        self.assertEqual(request.method, "PUT")
        self.assertEqual(request.url.path, webpay._TRANSACTIONS_PATH + "/" + TOKEN)
        self.assertEqual(request.content, b"")
        self.assertEqual(result.status, "AUTHORIZED")
        self.assertEqual(result.amount, 12000)
        self.assertEqual(result.response_code, 0)
        self.assertEqual(result.transaction_id, "0910")
        self.assertEqual(result.raw, COMMIT)

    def test_production_requires_both_credentials_before_network(self):
        settings.TRANSBANK_ENVIRONMENT = "production"
        for code, key in (("", ""), ("fixture-code", ""), ("", "synthetic-private-key")):
            settings.TRANSBANK_COMMERCE_CODE = code
            settings.TRANSBANK_API_KEY = key
            self.deny(lambda: webpay.commit_webpay_transaction(TOKEN), 503)
        self.factory.assert_not_called()

    def test_production_uses_only_production_host_and_configured_credentials(self):
        settings.TRANSBANK_ENVIRONMENT = "production"
        settings.TRANSBANK_COMMERCE_CODE = "fixture-code"
        settings.TRANSBANK_API_KEY = "synthetic-private-key"
        webpay.commit_webpay_transaction(TOKEN)
        request = self.requests[0]
        self.assertEqual(request.url.host, "webpay3g.transbank.cl")
        self.assertEqual(request.headers["Tbk-Api-Key-Secret"], "synthetic-private-key")

    def test_unknown_environment_fails_closed(self):
        settings.TRANSBANK_ENVIRONMENT = "prod-typo"
        self.deny(lambda: webpay.commit_webpay_transaction(TOKEN), 503)
        self.factory.assert_not_called()

    def test_timeouts_do_not_retry_and_do_not_expose_provider_details(self):
        self.response = httpx.ReadTimeout(f"private {TOKEN} synthetic-private-key")
        self.deny(lambda: webpay.commit_webpay_transaction(TOKEN), 503)
        self.assertEqual(len(self.requests), 1)
        options = self.factory.call_args.kwargs
        self.assertFalse(options["follow_redirects"])
        self.assertFalse(options["trust_env"])
        self.assertEqual(options["timeout"].connect, 5)
        self.assertEqual(options["timeout"].read, 30)

    def test_redirects_and_provider_errors_are_not_followed_or_exposed(self):
        for code in (301, 302, 307, 400, 401, 429, 500, 503):
            with self.subTest(status=code):
                self.response = httpx.Response(code, headers={"Location": "https://untrusted.example"},
                                               text=f"private {TOKEN} synthetic-private-key")
                self.deny(lambda: webpay.commit_webpay_transaction(TOKEN), 503)
        self.assertEqual(len(self.requests), 8)

    def test_invalid_json_array_and_excessive_response_are_rejected(self):
        for content in (b"invalid", b"[]", b"null", b"x" * (webpay._MAX_RESPONSE_BYTES + 1)):
            self.response = httpx.Response(200, content=content)
            self.deny(lambda: webpay.commit_webpay_transaction(TOKEN), 503)

    def test_bad_commit_fields_cannot_be_treated_as_authorized(self):
        for key, value in (("response_code", False), ("response_code", "0"), ("amount", float("nan")),
                           ("amount", -1), ("amount", 12000.5), ("amount", "12000"),
                           ("buy_order", None), ("status", None)):
            with self.subTest(field=key, value_type=type(value).__name__):
                self.response = httpx.Response(200, content=json.dumps({**COMMIT, key: value}).encode())
                self.deny(lambda: webpay.commit_webpay_transaction(TOKEN), 503)

    def test_declined_payment_remains_declined(self):
        self.response = httpx.Response(200, json={**COMMIT, "status": "FAILED", "response_code": -1})
        result = webpay.commit_webpay_transaction(TOKEN)
        self.assertEqual(result.status, "FAILED")
        self.assertEqual(result.response_code, -1)

    def test_missing_response_fields_are_rejected(self):
        for key in ("status", "amount", "response_code", "buy_order"):
            data = COMMIT.copy()
            del data[key]
            self.response = httpx.Response(200, json=data)
            self.deny(lambda: webpay.commit_webpay_transaction(TOKEN), 503)

    def test_invalid_payment_destinations_are_rejected(self):
        for url in ("http://webpay3gint.transbank.cl/pay", "https://untrusted.example/pay",
                    "https://webpay3gint.transbank.cl.untrusted.example/pay",
                    "https://user@webpay3gint.transbank.cl/pay", "https://webpay3g.transbank.cl/pay"):
            self.response = httpx.Response(200, json={"token": TOKEN, "url": url})
            self.deny(lambda: webpay.create_webpay_transaction(**CREATE), 503)

    def test_invalid_token_is_rejected_before_network(self):
        for token in (None, "", "a" * 65, "../other", "abc?x=1", "abc\r\n", "https://other"):
            self.deny(lambda: webpay.commit_webpay_transaction(token), 400)
        self.factory.assert_not_called()

    def test_invalid_create_data_is_rejected_before_network(self):
        for key, value in (("amount", 0), ("amount", True), ("amount", -1), ("amount", 0.5),
                           ("buy_order", "x" * 27), ("session_id", "x" * 62),
                           ("return_url", "javascript:alert(1)")):
            self.deny(lambda: webpay.create_webpay_transaction(**{**CREATE, key: value}), 400)
        self.factory.assert_not_called()

    def test_production_rejects_non_https_callback(self):
        settings.TRANSBANK_ENVIRONMENT = "production"
        self.deny(lambda: webpay.create_webpay_transaction(**{**CREATE, "return_url": "http://example.com/callback"}), 400)
        self.factory.assert_not_called()

    def test_httpx_info_logs_do_not_expose_payment_token(self):
        with self.assertLogs("httpx", level="INFO") as logs:
            webpay.commit_webpay_transaction(TOKEN)
        self.assertNotIn(TOKEN, " ".join(logs.output))
        self.assertNotIn("Tbk-Api-Key", " ".join(logs.output))
