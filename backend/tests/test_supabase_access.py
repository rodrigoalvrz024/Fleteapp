import importlib.util
import io
import os
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch
from urllib.parse import parse_qs, urlsplit

from alembic.migration import MigrationContext
from alembic.operations import Operations

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("DATABASE_URL", "postgresql://postgres:postgres@localhost/muvv_test")
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from app.database import Base
import app.models  # Register all backend-owned tables for the coverage check.


ROOT = Path(__file__).resolve().parents[2]


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


verifier = load_module("verify_supabase_rls", ROOT / "scripts/verify-supabase-rls.py")
migration = load_module(
    "harden_freight_table_access",
    ROOT / "backend/alembic/versions/f2a4b6c8d010_harden_freight_table_access.py",
)


class SupabaseVerifierTests(unittest.TestCase):
    def setUp(self):
        self.conn = MagicMock()
        self.cursor = self.conn.cursor.return_value.__enter__.return_value
        self.rows = [(name, True) for name in verifier.TABLES]
        self.roles = [(name, False) for name in verifier.API_ROLES]
        self.cursor.fetchall.side_effect = [self.rows, [], [], self.roles]

    def run_main(self):
        output = io.StringIO()
        with patch.dict(os.environ, {"DATABASE_URL": "postgresql://localhost/test"}), \
                patch.object(verifier.psycopg2, "connect", return_value=self.conn) as connect, \
                patch("sys.stdout", output):
            result = verifier.main()
        return result, output.getvalue(), connect

    def test_verifier_covers_every_model_table_without_duplicates(self):
        self.assertEqual(set(verifier.TABLES), set(Base.metadata.tables))
        self.assertEqual(len(verifier.TABLES), len(set(verifier.TABLES)))

    def test_protected_tables_pass_with_read_only_bounded_connection(self):
        result, output, connect = self.run_main()
        self.assertEqual(result, 0)
        self.assertIn("RLS disabled: none", output)
        self.assertEqual(connect.call_args.kwargs["connect_timeout"], 10)
        self.assertIn("default_transaction_read_only=on", connect.call_args.kwargs["options"])
        self.assertIn("statement_timeout=7000", connect.call_args.kwargs["options"])
        self.conn.close.assert_called_once()
        self.conn.commit.assert_not_called()

    def test_missing_table_fails(self):
        self.rows.pop()
        result, output, _ = self.run_main()
        self.assertEqual(result, 1)
        self.assertIn("Missing tables: vehicles", output)

    def test_disabled_rls_fails(self):
        self.rows[0] = (self.rows[0][0], False)
        result, output, _ = self.run_main()
        self.assertEqual(result, 1)
        self.assertIn("RLS disabled: audit_events", output)

    def test_inherited_or_public_grant_fails(self):
        self.cursor.fetchall.side_effect = [
            self.rows, [("freight_chat_messages", "anon", "SELECT")], [], self.roles,
        ]
        result, output, _ = self.run_main()
        self.assertEqual(result, 1)
        self.assertIn("freight_chat_messages: anon SELECT", output)
        query, params = self.cursor.execute.call_args_list[1].args
        self.assertIn("has_table_privilege(r.oid, c.oid, p.privilege)", query)
        self.assertEqual(params, (verifier.TABLES, list(verifier.API_ROLES)))

    def test_column_only_grant_fails(self):
        self.cursor.fetchall.side_effect = [
            self.rows, [], [("trip_feedback", "authenticated", "SELECT")], self.roles,
        ]
        result, output, _ = self.run_main()
        self.assertEqual(result, 1)
        self.assertIn("Effective anon/authenticated column_grants: 1", output)
        query = self.cursor.execute.call_args_list[2].args[0]
        self.assertIn("has_any_column_privilege", query)

    def test_absent_api_roles_do_not_produce_false_success(self):
        self.roles.clear()
        result, output, _ = self.run_main()
        self.assertEqual(result, 1)
        self.assertIn("Missing API roles: anon, authenticated", output)

    def test_api_role_bypassing_rls_fails(self):
        self.roles[0] = ("anon", True)
        result, output, _ = self.run_main()
        self.assertEqual(result, 1)
        self.assertIn("API roles bypassing RLS: anon", output)

    def test_query_failure_closes_connection_and_redacts_error(self):
        self.cursor.execute.side_effect = RuntimeError("private-token-and-host")
        result, output, _ = self.run_main()
        self.assertEqual(result, 2)
        self.assertIn("RuntimeError", output)
        self.assertNotIn("private-token-and-host", output)
        self.conn.close.assert_called_once()

    def test_connection_failure_does_not_echo_credentials(self):
        output = io.StringIO()
        with patch.dict(os.environ, {"DATABASE_URL": "postgresql://localhost/test"}), \
                patch.object(verifier.psycopg2, "connect", side_effect=RuntimeError("private-password")), \
                patch("sys.stdout", output):
            self.assertEqual(verifier.main(), 2)
        self.assertNotIn("private-password", output.getvalue())

    def test_missing_database_url_fails(self):
        with patch.dict(os.environ, {"DATABASE_URL": ""}):
            with self.assertRaises(RuntimeError):
                verifier._database_url()

    def test_tls_cannot_be_disabled_but_stronger_verification_is_preserved(self):
        for sslmode, expected in ((None, "require"), ("disable", "require"),
                                  ("prefer", "require"), ("verify-full", "verify-full")):
            with self.subTest(sslmode=sslmode):
                url = "postgresql://localhost/test?application_name=muvv"
                if sslmode:
                    url += "&sslmode=" + sslmode
                with patch.dict(os.environ, {"DATABASE_URL": url}):
                    query = parse_qs(urlsplit(verifier._database_url()).query)
                self.assertEqual(query["sslmode"], [expected])
                self.assertEqual(query["application_name"], ["muvv"])


class SupabaseMigrationTests(unittest.TestCase):
    def test_upgrade_generates_scoped_postgresql_hardening_sql(self):
        output = io.StringIO()
        context = MigrationContext.configure(
            dialect_name="postgresql", opts={"as_sql": True, "output_buffer": output},
        )
        with Operations.context(context):
            migration.upgrade()
        sql = output.getvalue()
        for table in ("freight_cargo_photos", "freight_chat_messages",
                      "freight_driver_declines", "trip_feedback"):
            self.assertIn("'" + table + "'", sql)
        self.assertIn("ENABLE ROW LEVEL SECURITY", sql)
        self.assertIn("FROM PUBLIC", sql)
        self.assertIn("ARRAY['anon', 'authenticated']", sql)
        self.assertIn("pg_get_serial_sequence", sql)
        self.assertNotIn("FORCE ROW LEVEL SECURITY", sql)
        self.assertNotIn("CREATE POLICY", sql)
        self.assertNotIn("DROP TABLE", sql)
        self.assertEqual(migration.down_revision, "e1f0a2b3c4d5")

    def test_downgrade_preserves_security(self):
        with patch.object(migration, "op") as op:
            migration.downgrade()
        op.execute.assert_not_called()


if __name__ == "__main__":
    unittest.main()
