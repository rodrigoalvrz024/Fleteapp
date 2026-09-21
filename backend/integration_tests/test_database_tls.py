"""Real libpq TLS checks; invoked only by the disposable PostgreSQL runner."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

import psycopg2
from sqlalchemy.engine import make_url


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/verify-database-tls.py"
spec = importlib.util.spec_from_file_location("database_tls_verifier", SCRIPT)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


@unittest.skipUnless(os.environ.get("MUVV_ISOLATED_TLS_TEST") == "1", "Disposable TLS cluster required")
class DatabaseTlsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parameters = verifier.connection_parameters(os.environ)
        data = Path(os.environ["MUVV_TLS_FIXTURE"]).resolve()
        scratch = (ROOT / ".local-tools/rls-tests").resolve()
        if (data.name != "data" or data.parent.parent != scratch
                or not data.parent.name.startswith("run-")
                or cls.parameters["host"] != "127.0.0.1"
                or cls.parameters["dbname"] != "postgres"
                or cls.parameters["user"] != "muvv_test_superuser"
                or Path(cls.parameters["sslrootcert"]).resolve() != data / "test-ca.crt"):
            raise RuntimeError("Only a disposable loopback fixture is permitted")
        cls.wrong_ca = str(data / "wrong-ca.crt")

    def assert_verified_connection(self):
        conn = psycopg2.connect(**self.parameters)
        try:
            self.assertTrue(conn.info.ssl_in_use)
            self.assertIn(conn.info.ssl_attribute("protocol"), {"TLSv1.2", "TLSv1.3"})
            self.assertEqual(conn.get_dsn_parameters()["sslmode"], "verify-full")
        finally:
            conn.close()

    def test_valid_ca_and_server_identity_connect(self):
        self.assert_verified_connection()
        verifier.inspect_connection(self.parameters)

    def test_untrusted_ca_fails_without_plaintext_fallback(self):
        self.assert_verified_connection()
        with self.assertRaises(psycopg2.OperationalError) as caught:
            psycopg2.connect(**{**self.parameters, "sslrootcert": self.wrong_ca})
        self.assertIn("certificate verify failed", str(caught.exception).lower())
        self.assert_verified_connection()

    def test_wrong_hostname_fails_on_the_same_reachable_server(self):
        self.assert_verified_connection()
        # hostaddr fixes transport to loopback; host tests certificate identity without DNS.
        with self.assertRaises(psycopg2.OperationalError) as caught:
            psycopg2.connect(**{**self.parameters, "host": "wrong-fixture.invalid", "hostaddr": "127.0.0.1"})
        self.assertIn("does not match host name", str(caught.exception).lower())
        self.assert_verified_connection()

    def run_verifier(self, *, wrong_ca=False):
        environment = dict(os.environ)
        if wrong_ca:
            url = make_url(environment["DATABASE_URL"])
            environment["DATABASE_URL"] = url.update_query_dict({"sslrootcert": self.wrong_ca}).render_as_string(hide_password=False)
        result = subprocess.run(
            [sys.executable, "-B", str(SCRIPT), "--connect-read-only"],
            env=environment, cwd=Path(os.environ["MUVV_TLS_FIXTURE"]).parent,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", timeout=20,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        self.assertEqual(result.stderr, "")
        self.assertNotIn(self.parameters["password"], result.stdout)
        self.assertNotIn(self.parameters["sslrootcert"], result.stdout)
        report = json.loads(result.stdout)
        self.assertFalse(report["deployment_approved"])
        self.assertFalse(report["application_configuration_changed"])
        return result.returncode, report

    def test_cli_readonly_success_does_not_approve_deployment(self):
        code, report = self.run_verifier()
        self.assertEqual(code, 0)
        self.assertTrue(report["connection_verified"])
        self.assertEqual(report["result"], "connection_verified")

    def test_cli_bad_ca_fails_with_sanitized_output(self):
        self.assert_verified_connection()
        code, report = self.run_verifier(wrong_ca=True)
        self.assertEqual(code, 2)
        self.assertFalse(report["connection_verified"])
        self.assertEqual(report["result"], "verification_failed_check_privately")
        self.assert_verified_connection()
