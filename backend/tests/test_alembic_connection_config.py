import importlib.util
import runpy
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

from alembic.config import Config
from sqlalchemy.engine import URL
import sqlalchemy.ext.declarative
import sqlalchemy.orm


ROOT = Path(__file__).resolve().parents[1]
DATABASE_SCRIPT = Path(importlib.util.find_spec("app.database").origin)


class AlembicConnectionConfigTests(unittest.TestCase):
    def configure(self, url, *, offline=False):
        settings = SimpleNamespace(DATABASE_URL=url, DB_CONNECT_TIMEOUT_SECONDS=7,
                                   DB_POOL_SIZE=5, DB_MAX_OVERFLOW=2, DB_POOL_TIMEOUT_SECONDS=5)
        core = ModuleType("app.core.config")
        core.settings = settings
        with patch.dict("sys.modules", {"app.core.config": core}), patch("sqlalchemy.create_engine") as api_create:
            api = runpy.run_path(str(DATABASE_SCRIPT))
        database = ModuleType("app.database")
        database.__dict__.update({key: api[key] for key in ("Base", "DATABASE_URL", "connect_args")})
        context = MagicMock()
        context.config = Config()
        context.is_offline_mode.return_value = offline
        with patch.dict("sys.modules", {"app.database": database, "app.models": ModuleType("app.models"),
                                        "app.core.config": core}), patch("alembic.context", context), \
                patch("sqlalchemy.engine_from_config") as migration_create, patch.object(sys, "path", list(sys.path)):
            runpy.run_path(str(ROOT / "alembic/env.py"))
        return api_create, migration_create, context

    def test_postgres_alias_matches_api_normalization(self):
        api, migrations, _ = self.configure("postgres://fixture:synthetic@localhost/test_db")
        self.assertEqual(migrations.call_args.args[0]["sqlalchemy.url"], api.call_args.args[0])
        self.assertTrue(migrations.call_args.args[0]["sqlalchemy.url"].startswith("postgresql://"))

    def test_percent_encoded_credentials_and_ca_path_survive_config(self):
        url = URL.create("postgresql+psycopg2", username="fixture", password="synthetic%25@secret",
                         host="localhost", database="test_db",
                         query={"sslmode": "verify-full", "sslrootcert": "C:/fixture with spaces/ca.crt"}).render_as_string(hide_password=False)
        api, migrations, _ = self.configure(url)
        self.assertEqual(migrations.call_args.args[0]["sqlalchemy.url"], url)
        self.assertEqual(api.call_args.args[0], url)

    def test_migration_uses_same_bounded_connect_timeout_as_api(self):
        api, migrations, _ = self.configure("postgresql://fixture:synthetic@localhost/test_db")
        self.assertEqual(migrations.call_args.kwargs["connect_args"], api.call_args.kwargs["connect_args"])
        self.assertEqual(migrations.call_args.kwargs["connect_args"], {"connect_timeout": 7})

    def test_offline_migration_preserves_tls_url_without_connecting(self):
        url = "postgres://fixture:synthetic%40secret@localhost/test_db?sslmode=verify-full&sslrootcert=%2Fapp%2Fca.crt"
        api, migrations, context = self.configure(url, offline=True)
        migrations.assert_not_called()
        self.assertEqual(context.configure.call_args.kwargs["url"], api.call_args.args[0])

    def test_existing_url_without_tls_settings_is_not_changed(self):
        url = "postgresql://fixture:synthetic@localhost/test_db"
        _, migrations, _ = self.configure(url)
        self.assertEqual(migrations.call_args.args[0]["sqlalchemy.url"], url)
