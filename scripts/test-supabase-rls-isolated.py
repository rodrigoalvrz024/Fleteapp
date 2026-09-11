"""Exercise the RLS migration on a disposable, loopback-only PostgreSQL cluster."""

import argparse
import importlib.util
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest

from alembic.migration import MigrationContext
from alembic.operations import Operations
import psycopg2
from psycopg2 import sql
from sqlalchemy import create_engine, URL


ROOT = Path(__file__).resolve().parents[1]
TABLES = (
    "freight_cargo_photos", "freight_chat_messages",
    "freight_driver_declines", "trip_feedback",
)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


migration = load_module(
    "rls_migration",
    ROOT / "backend/alembic/versions/f2a4b6c8d010_harden_freight_table_access.py",
)
verifier = load_module("rls_verifier", ROOT / "scripts/verify-supabase-rls.py")


class AccessTests(unittest.TestCase):
    connection_options = None
    engine = None

    def setUp(self):
        self.conn = psycopg2.connect(**self.connection_options)
        self.addCleanup(self.conn.close)
        self.addCleanup(self.conn.rollback)
        self.cursor = self.conn.cursor()
        self.addCleanup(self.cursor.close)

    def test_owner_keeps_rows_and_can_create_update_delete(self):
        self.cursor.execute("SET ROLE muvv_backend_owner")
        for table in TABLES:
            with self.subTest(table=table):
                name = sql.Identifier(table)
                self.cursor.execute(sql.SQL("SELECT payload FROM {} ORDER BY id").format(name))
                self.assertEqual(self.cursor.fetchall(), [("synthetic fixture",)])
                self.cursor.execute(
                    sql.SQL("INSERT INTO {} (payload) VALUES ('temporary') RETURNING id").format(name)
                )
                row_id = self.cursor.fetchone()[0]
                self.cursor.execute(sql.SQL("UPDATE {} SET payload='updated' WHERE id=%s").format(name), (row_id,))
                self.assertEqual(self.cursor.rowcount, 1)
                self.cursor.execute(sql.SQL("DELETE FROM {} WHERE id=%s").format(name), (row_id,))
                self.assertEqual(self.cursor.rowcount, 1)

    def test_rls_enabled_without_forcing_table_owner(self):
        self.cursor.execute(
            "SELECT relrowsecurity, relforcerowsecurity FROM pg_class "
            "WHERE relnamespace='public'::regnamespace AND relname=ANY(%s)",
            (list(TABLES),),
        )
        self.assertEqual(self.cursor.fetchall(), [(True, False)] * len(TABLES))

    def test_api_roles_lose_table_and_sequence_privileges(self):
        for role in ("anon", "authenticated"):
            for table in TABLES:
                with self.subTest(role=role, table=table):
                    for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER"):
                        self.cursor.execute("SELECT has_table_privilege(%s, %s, %s)", (role, table, privilege))
                        self.assertFalse(self.cursor.fetchone()[0])
                    for privilege in ("USAGE", "SELECT", "UPDATE"):
                        self.cursor.execute(
                            "SELECT has_sequence_privilege(%s, pg_get_serial_sequence(%s,'id'), %s)",
                            (role, table, privilege),
                        )
                        self.assertFalse(self.cursor.fetchone()[0])

    def test_actual_select_is_denied_for_each_api_role(self):
        for role in ("anon", "authenticated"):
            for table in TABLES:
                self.cursor.execute("SAVEPOINT denied_access")
                self.cursor.execute(sql.SQL("SET LOCAL ROLE {}").format(sql.Identifier(role)))
                with self.assertRaises(psycopg2.errors.InsufficientPrivilege):
                    self.cursor.execute(sql.SQL("SELECT * FROM {}").format(sql.Identifier(table)))
                self.cursor.execute("ROLLBACK TO SAVEPOINT denied_access")

    def test_rls_still_denies_rows_if_table_grants_return(self):
        for role in ("anon", "authenticated"):
            for table in TABLES:
                self.cursor.execute("SAVEPOINT rls_access")
                self.cursor.execute(sql.SQL("GRANT SELECT, INSERT, UPDATE, DELETE ON {} TO {}").format(
                    sql.Identifier(table), sql.Identifier(role),
                ))
                self.cursor.execute(sql.SQL("SET LOCAL ROLE {}").format(sql.Identifier(role)))
                self.cursor.execute(sql.SQL("SELECT * FROM {}").format(sql.Identifier(table)))
                self.assertEqual(self.cursor.fetchall(), [])
                self.cursor.execute(sql.SQL("UPDATE {} SET payload='forbidden'").format(sql.Identifier(table)))
                self.assertEqual(self.cursor.rowcount, 0)
                self.cursor.execute(sql.SQL("DELETE FROM {}").format(sql.Identifier(table)))
                self.assertEqual(self.cursor.rowcount, 0)
                with self.assertRaises(psycopg2.errors.InsufficientPrivilege):
                    self.cursor.execute(sql.SQL("INSERT INTO {} (id,payload) VALUES (99,'forbidden')").format(sql.Identifier(table)))
                self.cursor.execute("ROLLBACK TO SAVEPOINT rls_access")

    def test_unrelated_table_is_not_changed(self):
        self.cursor.execute("SELECT relrowsecurity FROM pg_class WHERE oid='public.unrelated_fixture'::regclass")
        self.assertFalse(self.cursor.fetchone()[0])
        self.cursor.execute("SELECT payload FROM unrelated_fixture")
        self.assertEqual(self.cursor.fetchall(), [("unrelated fixture",)])

    def test_verifier_detects_real_public_and_column_grants(self):
        self.cursor.execute("GRANT SELECT ON freight_chat_messages TO PUBLIC")
        self.cursor.execute("GRANT SELECT(payload) ON trip_feedback TO authenticated")
        result = verifier.inspect_access(self.conn)
        self.assertIn(("freight_chat_messages", "anon", "SELECT"), result["grants"])
        self.assertIn(("trip_feedback", "authenticated", "SELECT"), result["column_grants"])

    def test_verifier_enforces_read_only_without_startup_options(self):
        options = {key: value for key, value in self.connection_options.items() if key != "options"}
        conn = psycopg2.connect(**options)
        try:
            verifier.begin_read_only_inspection(conn)
            with conn.cursor() as cursor:
                cursor.execute(
                    "SELECT current_setting('transaction_read_only'), "
                    "current_setting('statement_timeout'), current_setting('lock_timeout')"
                )
                self.assertEqual(cursor.fetchone(), ("on", "7s", "3s"))
                self.assertEqual(verifier.inspect_access(conn)["checked"], len(TABLES))
                with self.assertRaises(psycopg2.errors.ReadOnlySqlTransaction):
                    cursor.execute("UPDATE unrelated_fixture SET payload='forbidden'")
        finally:
            conn.close()

    def test_upgrade_is_repeatable_and_downgrade_keeps_protection(self):
        with self.engine.begin() as conn:
            conn.exec_driver_sql("SET LOCAL ROLE muvv_backend_owner")
            with Operations.context(MigrationContext.configure(conn)):
                migration.upgrade()
                migration.downgrade()
        self.cursor.execute(
            "SELECT bool_and(relrowsecurity) FROM pg_class "
            "WHERE relnamespace='public'::regnamespace AND relname=ANY(%s)", (list(TABLES),),
        )
        self.assertTrue(self.cursor.fetchone()[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", required=True, type=Path)
    parser.add_argument("--http", action="store_true", help="Also test real HTTP routes and the complete model schema with synthetic data.")
    parser.add_argument("--migrations", action="store_true", help="Also validate the complete Alembic history on a new, empty database.")
    parser.add_argument("--migration-start", choices=("empty", "models"), default="empty",
                        help="Test Alembic from empty, or simulate the legacy model-created schema on a fresh DB.")
    args = parser.parse_args()
    if args.migration_start != "empty" and not args.migrations:
        parser.error("--migration-start requires --migrations")
    scratch = (ROOT / ".local-tools" / "rls-tests").resolve()
    if not scratch.is_relative_to(ROOT.resolve()):
        raise RuntimeError("Temporary cluster directory must stay inside the workspace.")
    scratch.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="run-", dir=scratch)).resolve()
    data = run_dir / "data"
    password = secrets.token_urlsafe(32)
    password_file = run_dir / "password.txt"
    password_file.write_text(password, encoding="ascii")
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    child_env = {key: value for key, value in os.environ.items() if not key.startswith("PG")}
    hidden = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0

    def pg(name, *arguments):
        # A background postgres process can keep PIPE handles open on Windows.
        log_file = run_dir / (name + ".log")
        with log_file.open("a", encoding="utf8") as output:
            result = subprocess.run(
                [str(args.pg_bin / name), *map(str, arguments)],
                env=child_env, creationflags=hidden, stdin=subprocess.DEVNULL,
                stdout=output, stderr=subprocess.STDOUT, timeout=60,
            )
        if result.returncode:
            details = log_file.read_text(encoding="utf8", errors="replace")[-2000:]
            raise RuntimeError(f"{name} failed ({result.returncode}): {details}")
        return result

    engine = None
    try:
        pg("initdb.exe", "-D", data, "-U", "muvv_test_superuser", "--auth=scram-sha-256",
           "--pwfile", password_file, "--encoding=UTF8", "--locale=C")
        pg("pg_ctl.exe", "-D", data, "-l", run_dir / "server.log", "-o",
           f"-h 127.0.0.1 -p {port}", "-w", "-t", "30", "start")
        options = dict(host="127.0.0.1", port=port, dbname="postgres",
                       user="muvv_test_superuser", password=password, connect_timeout=5,
                       options="-c statement_timeout=10000 -c lock_timeout=5000")
        with psycopg2.connect(**options) as conn:
            with conn.cursor() as cur:
                cur.execute("CREATE ROLE muvv_backend_owner NOLOGIN NOSUPERUSER NOBYPASSRLS")
                cur.execute("CREATE ROLE anon NOLOGIN NOSUPERUSER NOBYPASSRLS")
                cur.execute("CREATE ROLE authenticated NOLOGIN NOSUPERUSER NOBYPASSRLS")
                cur.execute("GRANT CREATE ON SCHEMA public TO muvv_backend_owner")
                cur.execute("SET LOCAL ROLE muvv_backend_owner")
                for table in (*TABLES, "unrelated_fixture"):
                    name = sql.Identifier(table)
                    cur.execute(sql.SQL("CREATE TABLE {} (id SERIAL PRIMARY KEY, payload TEXT NOT NULL)").format(name))
                    payload = "unrelated fixture" if table == "unrelated_fixture" else "synthetic fixture"
                    cur.execute(sql.SQL("INSERT INTO {} (payload) VALUES (%s)").format(name), (payload,))
                    if table in TABLES:
                        cur.execute(sql.SQL("GRANT ALL ON {} TO PUBLIC, anon, authenticated").format(name))
                        cur.execute(sql.SQL("GRANT ALL ON SEQUENCE {} TO PUBLIC, anon, authenticated").format(
                            sql.Identifier(table + "_id_seq"),
                        ))
        engine = create_engine(
            URL.create(
                "postgresql+psycopg2", username=options["user"], password=password,
                host=options["host"], port=port, database="postgres",
            ),
            connect_args={"connect_timeout": 5, "options": options["options"]},
        )
        with engine.begin() as conn:
            conn.exec_driver_sql("SET LOCAL ROLE muvv_backend_owner")
            with Operations.context(MigrationContext.configure(conn)):
                migration.upgrade()
        AccessTests.connection_options = options
        AccessTests.engine = engine
        result = unittest.TextTestRunner(verbosity=2).run(
            unittest.defaultTestLoader.loadTestsFromTestCase(AccessTests)
        )
        if not result.wasSuccessful():
            return 1
        if args.migrations:
            migration_password = secrets.token_urlsafe(32)
            migration_database = "muvv_migration_" + secrets.token_hex(8)
            with psycopg2.connect(**options) as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "CREATE ROLE muvv_migration_owner LOGIN NOSUPERUSER NOCREATEDB "
                        "NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD %s", (migration_password,),
                    )
            conn = psycopg2.connect(**options)
            try:
                conn.autocommit = True
                with conn.cursor() as cur:
                    cur.execute(sql.SQL("CREATE DATABASE {} OWNER muvv_migration_owner").format(
                        sql.Identifier(migration_database),
                    ))
            finally:
                conn.close()
            migration_env = {key: value for key, value in os.environ.items()
                             if key.upper() in {"SYSTEMROOT", "WINDIR", "PATH", "TEMP", "TMP"}}
            migration_env.update(
                PYTHONPATH=str(ROOT / "backend"), PYTHONIOENCODING="utf-8",
                APP_ENV="test", RUN_STARTUP_MIGRATIONS="false",
                MUVV_ISOLATED_MIGRATION_TEST="1", MUVV_MIGRATION_DATABASE=migration_database,
                MUVV_MIGRATION_START=args.migration_start,
                SECRET_KEY=secrets.token_urlsafe(48),
                PGOPTIONS="-c statement_timeout=20000 -c lock_timeout=5000",
                DATABASE_URL=URL.create(
                    "postgresql+psycopg2", username="muvv_migration_owner", password=migration_password,
                    host="127.0.0.1", port=port, database=migration_database,
                ).render_as_string(hide_password=False),
            )
            completed = subprocess.run(
                [sys.executable, "-B", "-m", "unittest", "discover", "-v",
                 "-s", str(ROOT / "backend/integration_tests"), "-p", "test_migration_chain.py"],
                cwd=run_dir, env=migration_env, creationflags=hidden, timeout=180,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8",
            )
            print(completed.stdout, end="")
            if completed.returncode:
                return completed.returncode
        if args.http:
            http_password = secrets.token_urlsafe(32)
            database = "muvv_http_" + secrets.token_hex(8)
            with psycopg2.connect(**options) as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "CREATE ROLE muvv_http_owner LOGIN NOSUPERUSER NOCREATEDB "
                        "NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD %s", (http_password,),
                    )
            conn = psycopg2.connect(**options)
            try:
                conn.autocommit = True
                with conn.cursor() as cur:
                    cur.execute(sql.SQL("CREATE DATABASE {} OWNER muvv_http_owner").format(sql.Identifier(database)))
            finally:
                conn.close()
            # No inherited app credentials or .env: the worker runs in the new scratch directory.
            http_env = {key: value for key, value in os.environ.items()
                        if key.upper() in {"SYSTEMROOT", "WINDIR", "PATH", "TEMP", "TMP"}}
            http_env.update(
                PYTHONPATH=str(ROOT / "backend"), PYTHONIOENCODING="utf-8",
                APP_ENV="test", RUN_STARTUP_MIGRATIONS="false",
                MUVV_ISOLATED_HTTP_TEST="1", MUVV_HTTP_DATABASE=database,
                SECRET_KEY=secrets.token_urlsafe(48),
                DATABASE_URL=URL.create(
                    "postgresql+psycopg2", username="muvv_http_owner", password=http_password,
                    host="127.0.0.1", port=port, database=database,
                ).render_as_string(hide_password=False),
            )
            completed = subprocess.run(
                [sys.executable, "-B", "-m", "unittest", "discover", "-v",
                 "-s", str(ROOT / "backend/integration_tests"), "-p", "test_http_permissions.py"],
                cwd=run_dir, env=http_env, creationflags=hidden, timeout=180,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8",
            )
            print(completed.stdout, end="")
            return completed.returncode
        return 0
    finally:
        if engine is not None:
            engine.dispose()
        if (data / "postmaster.pid").exists():
            pg("pg_ctl.exe", "-D", data, "-m", "fast", "-w", "-t", "30", "stop")
        # Only delete the newly created test cluster, never an existing database.
        if run_dir.parent != scratch or not run_dir.name.startswith("run-"):
            raise RuntimeError("Unexpected temporary cluster path; cleanup refused.")
        shutil.rmtree(run_dir)
        print("Disposable cluster stopped and removed. No external database used.")


if __name__ == "__main__":
    raise SystemExit(main())
