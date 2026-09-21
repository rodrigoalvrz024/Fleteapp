"""Only run through test-supabase-rls-isolated.py --migrations."""

import os
from pathlib import Path
import re
import sys
import unittest
from contextlib import contextmanager
from time import monotonic
from datetime import datetime, timezone

from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.operations import Operations
from alembic.script import ScriptDirectory
from sqlalchemy import event, inspect, select, text
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.exc import DBAPIError


URL = make_url(os.environ.get("DATABASE_URL", "sqlite://"))
if not (
    os.environ.get("MUVV_ISOLATED_MIGRATION_TEST") == "1"
    and os.environ.get("APP_ENV") == "test"
    and URL.host == "127.0.0.1"
    and URL.username == "muvv_migration_owner"
    and re.fullmatch(r"muvv_migration_[0-9a-f]{16}", URL.database or "")
    and URL.database == os.environ.get("MUVV_MIGRATION_DATABASE")
    and not Path(".env").exists()
):
    raise RuntimeError("Use the disposable PostgreSQL runner; existing databases are forbidden.")


def guard_network(event, args):
    if event == "socket.connect" and isinstance(args[1], tuple):
        if args[1][0] != "127.0.0.1" or args[1][1] != URL.port:
            raise RuntimeError("Only the disposable PostgreSQL server is allowed.")


sys.addaudithook(guard_network)

from app.core.config import settings
from app.database import Base, SessionLocal, engine
import app.models


ROOT = Path(__file__).resolve().parents[1]


TLS_CONNECTIONS = []


def verify_fixture_tls(dbapi_connection, connection_record):
    if URL.query.get("sslmode") != "verify-full":
        return
    parameters = dbapi_connection.get_dsn_parameters()
    if (not dbapi_connection.info.ssl_in_use
            or dbapi_connection.info.ssl_attribute("protocol") not in {"TLSv1.2", "TLSv1.3"}
            or parameters.get("sslmode") != "verify-full"
            or parameters.get("sslrootcert") != URL.query["sslrootcert"]):
        raise RuntimeError("Expected verified TLS for every API and Alembic test connection")
    TLS_CONNECTIONS.append(True)


# Check every real SQLAlchemy connection before any fixture/migration SQL runs.
event.listen(Engine, "connect", verify_fixture_tls)


class MigrationChainTests(unittest.TestCase):
    @unittest.skipUnless(URL.query.get("sslmode") == "verify-full", "Run with --tls")
    def test_tls_api_and_alembic_connections_are_verified(self):
        before = len(TLS_CONNECTIONS)
        command.upgrade(self.config, "head")
        self.assertGreater(len(TLS_CONNECTIONS), before)
        self.assertGreaterEqual(len(TLS_CONNECTIONS), 2)

    @contextmanager
    def session_migration_fixture(self):
        # This suite already verifies a newly created, disposable local database.
        with engine.begin() as conn:
            conn.exec_driver_sql("CREATE SCHEMA session_migration_test")
            conn.exec_driver_sql("CREATE TABLE session_migration_test.users (id integer PRIMARY KEY)")
            conn.exec_driver_sql("INSERT INTO session_migration_test.users VALUES (1)")
        try:
            yield ScriptDirectory.from_config(self.config).get_revision("a7d2e9c1f630").module
        finally:
            with engine.begin() as conn:
                conn.exec_driver_sql("DROP SCHEMA session_migration_test CASCADE")

    def test_session_generation_backfills_zero_and_preserves_revocations(self):
        with self.session_migration_fixture() as migration:
            with engine.begin() as conn:
                conn.exec_driver_sql("SET LOCAL search_path = session_migration_test")
                with Operations.context(MigrationContext.configure(conn)):
                    migration.upgrade()
                    self.assertEqual(conn.exec_driver_sql("SELECT session_version FROM users").scalar_one(), 0)
                    conn.exec_driver_sql("UPDATE users SET session_version=7 WHERE id=1")
                    migration.upgrade()
                    conn.exec_driver_sql("INSERT INTO users (id) VALUES (2)")
                    self.assertEqual(conn.exec_driver_sql("SELECT session_version FROM users ORDER BY id").scalars().all(), [7, 0])

    def test_session_migration_sets_own_bounded_lock_timeout(self):
        with self.session_migration_fixture() as migration:
            with engine.connect() as blocker:
                blocker.exec_driver_sql("SELECT * FROM session_migration_test.users")
                with engine.connect() as contender:
                    contender.exec_driver_sql("SET LOCAL search_path = session_migration_test")
                    contender.exec_driver_sql("SET LOCAL lock_timeout = '0'")
                    contender.exec_driver_sql("SET LOCAL statement_timeout = '10s'")
                    started = monotonic()
                    with self.assertRaises(DBAPIError) as error:
                        with Operations.context(MigrationContext.configure(contender)):
                            migration.upgrade()
                    self.assertEqual(error.exception.orig.pgcode, "55P03")
                    self.assertLess(monotonic() - started, 9)
                    contender.rollback()
                blocker.rollback()

    @classmethod
    def setUpClass(cls):
        cls.addClassCleanup(engine.dispose)
        if settings.RUN_STARTUP_MIGRATIONS:
            raise RuntimeError("Automatic schema changes must be disabled.")
        with engine.connect() as conn:
            identity = conn.execute(text(
                "SELECT current_database(), current_user, rolsuper, rolbypassrls "
                "FROM pg_roles WHERE rolname=current_user"
            )).one()
            if tuple(identity) != (URL.database, "muvv_migration_owner", False, False):
                raise RuntimeError("Unexpected database or privileged role.")
            if inspect(conn).get_table_names(schema="public"):
                raise RuntimeError("Refusing to overwrite an existing schema.")
        cls.config = Config(str(ROOT / "alembic.ini"))
        cls.config.set_main_option("script_location", str(ROOT / "alembic"))
        cls.expected_head = ScriptDirectory.from_config(cls.config).get_current_head()
        cls.legacy = os.environ.get("MUVV_MIGRATION_START") == "models"
        if cls.legacy:
            # Simulate older startup-created tables only on the verified empty test DB.
            Base.metadata.create_all(engine)
            command.stamp(cls.config, "e1f0a2b3c4d5")
            from app.models import User, Driver, FreightRequest, Payment, DriverPayout
            with SessionLocal() as db:
                db.add_all([
                    User(id=1, email="driver@example.com", phone="+56900000001", full_name="Synthetic Driver",
                         hashed_password="synthetic-not-a-login", role="driver", account_roles=["client", "driver"]),
                    User(id=2, email="client@example.com", phone="+56900000002", full_name="Synthetic Client",
                         hashed_password="synthetic-not-a-login", role="client", account_roles=["client"]),
                ])
                db.flush()
                db.add(Driver(id=1, user_id=1, rut="synthetic", license_number="synthetic",
                              license_expiry=datetime(2030, 1, 1), status="approved"))
                db.flush()
                db.add(FreightRequest(id=1, client_id=2, driver_id=1, status="completed",
                                     origin_address="Synthetic origin", origin_lat=0, origin_lng=0,
                                     destination_address="Synthetic destination", destination_lat=1, destination_lng=1,
                                     cargo_description="Synthetic cargo", cargo_weight_kg=100,
                                     cargo_volume_m3=1, estimated_price=12000,
                                     client_pays=12000, driver_receives=10000, platform_fee=2000))
                db.flush()
                db.add(Payment(id=1, freight_id=1, amount=12000, method="transfer", status="authorized"))
                db.flush()
                db.add(DriverPayout(payment_id=1, freight_id=1, driver_id=1, amount=10000,
                                    status="paid", paid_at=datetime.now(timezone.utc), transfer_reference="synthetic-only"))
                db.commit()
        else:
            # Exercise the real history up to the last observed deployed revision.
            command.upgrade(cls.config, "e1f0a2b3c4d5")
        with engine.begin() as conn:
            cls.before = {}
            inspector = inspect(conn)
            quote = conn.dialect.identifier_preparer.quote
            for table in inspector.get_table_names(schema="public"):
                if table == "alembic_version":
                    continue
                columns = [column["name"] for column in inspector.get_columns(table)]
                rows = conn.exec_driver_sql(f"SELECT * FROM {quote(table)} ORDER BY id").all()
                cls.before[table] = (columns, rows)
            conn.exec_driver_sql("CREATE TABLE migration_unrelated (id integer PRIMARY KEY, value text)")
            conn.exec_driver_sql("INSERT INTO migration_unrelated VALUES (1, 'synthetic unchanged')")
            # Include column grants: REVOKE at table level alone does not remove them.
            conn.exec_driver_sql("GRANT USAGE ON SCHEMA public TO anon, authenticated")
            conn.exec_driver_sql("GRANT SELECT ON users TO PUBLIC")
            conn.exec_driver_sql("GRANT SELECT (email) ON users TO authenticated")
        # Exercise env.py and candidate revisions, never startup repairs.
        command.upgrade(cls.config, "head")

    def test_head_and_repeat_upgrade(self):
        with engine.connect() as conn:
            self.assertEqual(MigrationContext.configure(conn).get_current_revision(), self.expected_head)
        command.upgrade(self.config, "head")
        with engine.connect() as conn:
            self.assertEqual(MigrationContext.configure(conn).get_current_revision(), self.expected_head)

    def test_all_runtime_tables_and_columns_exist(self):
        with engine.connect() as conn:
            inspector = inspect(conn)
            tables = set(inspector.get_table_names(schema="public"))
            missing_tables = sorted(set(Base.metadata.tables) - tables)
            missing_columns = {}
            for name, model in Base.metadata.tables.items():
                if name in tables:
                    columns = {column["name"] for column in inspector.get_columns(name)}
                    missing = sorted(set(model.columns.keys()) - columns)
                    if missing:
                        missing_columns[name] = missing
            with self.subTest(check="tables"):
                self.assertEqual(missing_tables, [], f"Missing runtime tables: {missing_tables}")
            with self.subTest(check="columns"):
                self.assertEqual(missing_columns, {}, f"Missing runtime columns: {missing_columns}")

    def test_existing_rows_and_financial_states_unchanged(self):
        with engine.connect() as conn:
            quote = conn.dialect.identifier_preparer.quote
            for table, (columns, before) in self.before.items():
                names = ", ".join(quote(name) for name in columns)
                after = conn.exec_driver_sql(f"SELECT {names} FROM {quote(table)} ORDER BY id").all()
                self.assertEqual(after, before, f"Existing rows changed in {table}")
            if self.legacy:
                self.assertEqual(conn.exec_driver_sql("SELECT status::text, amount FROM payments").all(), [("authorized", 12000)])
                self.assertEqual(conn.exec_driver_sql("SELECT status::text, amount FROM driver_payouts").all(), [("paid", 10000)])

    def test_runtime_can_select_all_models(self):
        with engine.connect() as conn:
            for table in Base.metadata.sorted_tables:
                with self.subTest(table=table.name):
                    conn.execute(select(table).limit(1)).all()

    def test_private_tables_owner_and_api_roles(self):
        with engine.connect() as conn:
            for table in Base.metadata.tables:
                with self.subTest(table=table):
                    protection = conn.execute(text(
                        "SELECT relrowsecurity, relforcerowsecurity FROM pg_class "
                        "WHERE oid=to_regclass(:table)"
                    ), {"table": "public." + table}).one()
                    self.assertEqual(tuple(protection), (True, False))
                    for role in ("anon", "authenticated"):
                        for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE"):
                            allowed = conn.execute(text(
                                "SELECT has_table_privilege(:role, :table, :privilege), "
                                "has_any_column_privilege(:role, :table, :privilege)"
                            ) if privilege != "DELETE" else text(
                                "SELECT has_table_privilege(:role, :table, :privilege), false"
                            ), {"role": role, "table": table, "privilege": privilege}).one()
                            self.assertEqual(tuple(allowed), (False, False))

    def test_unrelated_table_preserved(self):
        with engine.connect() as conn:
            self.assertEqual(conn.exec_driver_sql("SELECT * FROM migration_unrelated").all(), [(1, "synthetic unchanged")])
            self.assertFalse(conn.exec_driver_sql(
                "SELECT relrowsecurity FROM pg_class WHERE oid='public.migration_unrelated'::regclass"
            ).scalar_one())

    def test_new_tables_preserve_constraints_and_indexes(self):
        with engine.connect() as conn:
            inspector = inspect(conn)
            for name in ("audit_events", "data_privacy_requests", "driver_payouts",
                         "driver_review_audits", "password_reset_tokens", "user_consents"):
                model = Base.metadata.tables[name]
                columns = {column["name"]: column for column in inspector.get_columns(name)}
                self.assertEqual({key: value["nullable"] for key, value in columns.items()},
                                 {column.name: column.nullable for column in model.columns})
                self.assertEqual(inspector.get_pk_constraint(name)["constrained_columns"], ["id"])
                actual_indexes = {index["name"]: (tuple(index["column_names"]), bool(index["unique"]))
                                  for index in inspector.get_indexes(name) if not index.get("duplicates_constraint")}
                expected_indexes = {index.name: (tuple(column.name for column in index.columns), bool(index.unique))
                                    for index in model.indexes}
                self.assertEqual(actual_indexes, expected_indexes)
                expected_fks = {(fk.parent.name, fk.column.table.name, fk.column.name) for fk in model.foreign_keys}
                actual_fks = {(fk["constrained_columns"][0], fk["referred_table"], fk["referred_columns"][0])
                              for fk in inspector.get_foreign_keys(name)}
                self.assertEqual(actual_fks, expected_fks)
            payout_unique = {tuple(item["column_names"]) for item in inspector.get_unique_constraints("driver_payouts")}
            self.assertTrue({("payment_id",), ("freight_id",)}.issubset(payout_unique))

    def test_repeat_migration_and_downgrade_do_not_delete_data(self):
        migration = ScriptDirectory.from_config(self.config).get_revision(self.expected_head).module
        with engine.begin() as conn:
            before = {table.name: conn.execute(select(table).order_by(table.c.id)).all()
                      for table in Base.metadata.sorted_tables}
            with Operations.context(MigrationContext.configure(conn)):
                migration.upgrade()
                with self.assertRaisesRegex(RuntimeError, "Session revocation cannot be discarded"):
                    migration.downgrade()
            after = {table.name: conn.execute(select(table).order_by(table.c.id)).all()
                     for table in Base.metadata.sorted_tables}
            self.assertEqual(after, before)


if __name__ == "__main__":
    unittest.main()
