import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch
from urllib.parse import urlencode


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("database_tls_verifier", ROOT / "scripts/verify-database-tls.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class DatabaseTlsVerifierTests(unittest.TestCase):
    def setUp(self):
        self.directory = self.enterContext(tempfile.TemporaryDirectory())
        self.ca = Path(self.directory) / "test-ca.crt"
        self.ca.touch()  # Only a path fixture; no claim of a valid certificate.
        self.query = {"sslmode": "verify-full", "sslrootcert": str(self.ca)}
        self.connect = self.enterContext(patch.object(verifier.psycopg2, "connect"))

    def environment(self, query=None, scheme="postgresql"):
        return {"DATABASE_URL": f"{scheme}://test:private-secret@db.example.invalid/test_db?" +
                urlencode(self.query if query is None else query)}

    def run_check(self, env=None, argv=None):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = verifier.main(argv or [], self.environment() if env is None else env)
        text = output.getvalue()
        self.assertNotIn("private-secret", text)
        self.assertNotIn("example.invalid", text)
        self.assertNotIn(self.directory, text)
        return code, json.loads(text)

    def ready_connection(self):
        conn = self.connect.return_value
        conn.info.ssl_in_use = True
        conn.info.ssl_attribute.return_value = "TLSv1.3"
        conn.get_dsn_parameters.return_value = verifier.connection_parameters(self.environment())
        conn.cursor.return_value.__enter__.return_value.fetchone.return_value = ("on",)
        return conn

    def test_default_is_offline_and_does_not_approve_deployment(self):
        code, result = self.run_check()
        self.assertEqual(code, 0)
        self.assertEqual(result["result"], "configuration_only")
        self.assertFalse(result["connection_verified"])
        self.assertFalse(result["deployment_approved"])
        self.connect.assert_not_called()

    def test_postgres_and_psycopg2_urls_supported(self):
        for scheme in ("postgres", "postgresql", "postgresql+psycopg2"):
            with self.subTest(scheme=scheme):
                self.assertEqual(self.run_check(self.environment(scheme=scheme))[0], 0)
        self.connect.assert_not_called()

    def test_offline_does_not_access_certificate_filesystem(self):
        with patch.object(verifier.Path, "is_file") as exists:
            self.assertEqual(self.run_check()[0], 0)
            exists.assert_not_called()

    def test_unc_certificate_is_rejected_before_filesystem_access(self):
        with patch.object(verifier.Path, "is_file") as exists:
            for path in (r"\\server\share\ca.crt", "//server/share/ca.crt", r"\\?\C:\ca.crt",
                         "/\\server/share/ca.crt"):
                for argv in ([], ["--connect-read-only"]):
                    self.assertEqual(self.run_check(self.environment({**self.query, "sslrootcert": path}), argv)[0], 1)
            exists.assert_not_called()

    def test_explicit_zero_port_is_not_replaced(self):
        env = self.environment()
        env["DATABASE_URL"] = env["DATABASE_URL"].replace(".invalid/test_db", ".invalid:0/test_db")
        self.assertEqual(self.run_check(env, ["--connect-read-only"])[0], 1)
        self.connect.assert_not_called()

    def test_weak_or_missing_tls_modes_fail_without_network(self):
        for mode in (None, "disable", "allow", "prefer", "require", "verify-ca"):
            query = {"sslrootcert": str(self.ca)}
            if mode is not None:
                query["sslmode"] = mode
            with self.subTest(mode=mode):
                self.assertEqual(self.run_check(self.environment(query), ["--connect-read-only"])[0], 1)
        self.connect.assert_not_called()

    def test_missing_and_relative_ca_configuration_fail(self):
        for path in ("", "root.crt", "system"):
            with self.subTest(path=path):
                self.assertEqual(self.run_check(self.environment({**self.query, "sslrootcert": path}))[0], 1)

    def test_ca_file_existence_checked_only_when_opted_in(self):
        for path in (str(self.ca.parent / "missing.crt"), self.directory):
            with self.subTest(path=path):
                env = self.environment({**self.query, "sslrootcert": path})
                self.assertEqual(self.run_check(env)[0], 0)
                self.assertEqual(self.run_check(env, ["--connect-read-only"])[0], 1)
        self.connect.assert_not_called()

    def test_duplicate_and_redirecting_parameters_fail(self):
        env = self.environment()
        env["DATABASE_URL"] += "&sslmode=verify-full"
        self.assertEqual(self.run_check(env)[0], 1)
        for name in ("host", "hostaddr", "service", "options", "sslcert", "connect_timeout", "gssencmode"):
            self.assertEqual(self.run_check(self.environment({**self.query, name: "private-secret"}))[0], 1)
        self.connect.assert_not_called()

    def test_inherited_libpq_settings_require_review(self):
        for key in ("PGSERVICE", "PGHOST", "PGOPTIONS", "PGSSLROOTCERT"):
            self.assertEqual(self.run_check({**self.environment(), key: "private-secret"})[0], 1)

    def test_invalid_urls_and_credentials_never_leak(self):
        for value in ("", "private-secret", "postgresql://[private-secret", "sqlite://",
                      "postgresql://test@localhost/test", "postgresql://test:private-secret@/test",
                      "postgresql://test:private-secret@localhost:bad/test"):
            self.assertEqual(self.run_check({"DATABASE_URL": value})[0], 1)
        self.connect.assert_not_called()

    def test_unknown_command_line_argument_is_redacted(self):
        self.assertEqual(self.run_check(argv=["--private-secret"])[0], 1)
        self.connect.assert_not_called()

    def test_opt_in_uses_verified_tls_and_only_readonly_metadata(self):
        conn = self.ready_connection()
        code, result = self.run_check(argv=["--connect-read-only"])
        self.assertEqual(code, 0)
        self.assertTrue(result["connection_verified"])
        self.assertFalse(result["deployment_approved"])
        params = self.connect.call_args.kwargs
        self.assertEqual((params["sslmode"], params["gssencmode"], params["connect_timeout"]),
                         ("verify-full", "disable", 10))
        self.assertEqual(params["ssl_min_protocol_version"], "TLSv1.2")
        conn.set_session.assert_called_once_with(readonly=True, autocommit=False)
        sql = [call.args[0] for call in conn.cursor.return_value.__enter__.return_value.execute.call_args_list]
        self.assertEqual(sql, ["SET LOCAL statement_timeout = '7s'", "SET LOCAL lock_timeout = '3s'",
                               "SHOW transaction_read_only"])
        conn.rollback.assert_called_once()
        conn.close.assert_called_once()

    def test_tls_and_readonly_failures_close_connection_without_approval(self):
        for failure in ("plaintext", "old_protocol", "dsn", "readonly", "query"):
            with self.subTest(failure=failure):
                self.connect.return_value = MagicMock()
                conn = self.ready_connection()
                if failure == "plaintext":
                    conn.info.ssl_in_use = False
                elif failure == "old_protocol":
                    conn.info.ssl_attribute.return_value = "TLSv1.1"
                elif failure == "dsn":
                    conn.get_dsn_parameters.return_value["sslmode"] = "prefer"
                elif failure == "readonly":
                    conn.cursor.return_value.__enter__.return_value.fetchone.return_value = ("off",)
                else:
                    conn.cursor.side_effect = RuntimeError("private-secret")
                code, result = self.run_check(argv=["--connect-read-only"])
                self.assertEqual(code, 2)
                self.assertFalse(result["connection_verified"])
                conn.close.assert_called_once()

    def test_connection_error_does_not_print_server_exception(self):
        self.connect.side_effect = RuntimeError("private-secret db.example.invalid")
        code, result = self.run_check(argv=["--connect-read-only"])
        self.assertEqual(code, 2)
        self.assertFalse(result["connection_verified"])


if __name__ == "__main__":
    unittest.main()
