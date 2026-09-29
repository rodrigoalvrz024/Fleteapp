import os
import unittest
from unittest.mock import patch, Mock

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("DATABASE_URL", "postgresql://localhost/synthetic")
os.environ.setdefault("SECRET_KEY", "synthetic-preregistration-tests-only-key")

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import settings
from app.database import get_db
from app.models.driver_preregistration import DriverPreregistration
from app.routers import driver_preregistrations as route
from app.services import preregistration_sheets as sheets


class PreregistrationTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
        DriverPreregistration.__table__.create(self.engine)
        self.db = Session(self.engine)
        self.addCleanup(self.engine.dispose)
        self.addCleanup(self.db.close)
        app = FastAPI()
        app.include_router(route.router)
        app.dependency_overrides[get_db] = lambda: self.db
        self.client = self.enterContext(TestClient(app))
        self.enterContext(patch.object(settings, "DRIVER_PREREGISTRATION_ENABLED", True))
        self.enterContext(patch.object(settings, "LAUNCH_CLIENT_IP_SOURCE", "peer"))
        self.enterContext(patch.object(route, "check_rate_limit"))
        self.sync = self.enterContext(patch.object(route, "sync_preregistration"))
        self.payload = dict(full_name="Conductor Prueba", email="prueba@example.com", phone="9 1234 5678",
                            commune="Puente Alto", vehicle_type="furgon", contact_consent=True,
                            consent_version="preregistro-2026-09-v1")

    def send(self, **overrides):
        return self.client.post("/public/driver-preregistrations", json={**self.payload, **overrides})

    def test_save_consent_phone_and_duplicate_does_not_overwrite(self):
        self.assertEqual(self.send().status_code, 202)
        self.assertEqual(self.send(email="PRUEBA@example.com", full_name="Otra persona", marketing_consent=True).json(), {"status": "received"})
        record = self.db.query(DriverPreregistration).one()
        self.assertEqual(record.full_name, "Conductor Prueba")
        self.assertEqual(record.phone, "+56912345678")
        self.assertFalse(record.marketing_consent)
        self.assertTrue(record.contact_consent)
        self.assertIsNone(record.sheets_synced_at)
        self.sync.assert_called_once()

    def test_rejects_missing_consent_invalid_phone_and_extra_fields(self):
        for override in ({"contact_consent": False}, {"phone": "+1 555 010 1000"},
                         {"consent_version": "old"}, {"vehicle_type": "inventado"}, {"role": "admin"}):
            self.assertEqual(self.send(**override).status_code, 422)
        self.assertEqual(self.db.query(DriverPreregistration).count(), 0)

    def test_honeypot_and_disabled_feature_do_not_store(self):
        self.assertEqual(self.send(website="spam").status_code, 202)
        with patch.object(settings, "DRIVER_PREREGISTRATION_ENABLED", False):
            self.assertEqual(self.send().status_code, 503)
        self.assertEqual(self.db.query(DriverPreregistration).count(), 0)
        self.assertEqual(self.client.get("/public/driver-preregistrations").status_code, 405)

    def test_storage_failure_never_reports_success(self):
        with patch.object(self.db, "commit", side_effect=SQLAlchemyError("private")):
            response = self.send()
        self.assertEqual(response.status_code, 503)
        self.assertNotIn("private", response.text)
        self.assertEqual(self.db.query(DriverPreregistration).count(), 0)
        self.sync.assert_not_called()

    def test_sheet_failure_remains_pending_then_retries_once(self):
        self.send()
        with patch.object(sheets, "SessionLocal", sessionmaker(bind=self.engine)), \
             patch.object(settings, "PREREGISTRATION_SHEETS_ID", "synthetic"), \
             patch.object(settings, "PREREGISTRATION_SHEETS_CREDENTIALS_JSON", "{}"), \
             patch.object(sheets, "write_sheet_entry", side_effect=RuntimeError("private")):
            self.assertEqual(sheets.retry_pending(), (0, 1))
        self.db.expire_all()
        self.assertIsNone(self.db.query(DriverPreregistration).one().sheets_synced_at)
        with patch.object(sheets, "SessionLocal", sessionmaker(bind=self.engine)), \
             patch.object(settings, "PREREGISTRATION_SHEETS_ID", "synthetic"), \
             patch.object(settings, "PREREGISTRATION_SHEETS_CREDENTIALS_JSON", "{}"), \
             patch.object(sheets, "write_sheet_entry") as write:
            self.assertEqual(sheets.retry_pending(), (1, 1))
            self.assertEqual(sheets.retry_pending(), (0, 0))
            write.assert_called_once()

    def test_sheet_retry_targets_same_row_and_uses_raw_values(self):
        self.send(full_name="=IMPORTXML prueba")
        entry = self.db.query(DriverPreregistration).one()
        session = Mock()
        with patch.object(settings, "PREREGISTRATION_SHEETS_ID", "synthetic"), \
             patch.object(settings, "PREREGISTRATION_SHEETS_CREDENTIALS_JSON", "{}"), \
             patch.object(sheets.Credentials, "from_service_account_info"), \
             patch.object(sheets, "AuthorizedSession") as auth:
            auth.return_value.__enter__.return_value = session
            sheets.write_sheet_entry(entry)
            sheets.write_sheet_entry(entry)
        self.assertEqual(session.put.call_args_list[1], session.put.call_args_list[3])
        self.assertEqual(session.put.call_args.kwargs["params"], {"valueInputOption": "RAW"})


if __name__ == "__main__":
    unittest.main()
