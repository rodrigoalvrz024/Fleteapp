import importlib.util
import os
from pathlib import Path
from unittest import TestCase
from unittest.mock import patch

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("DATABASE_URL", "postgresql://localhost/synthetic")
os.environ.setdefault("SECRET_KEY", "synthetic-support-unit-test-key-not-a-real-secret")

from alembic.migration import MigrationContext
from alembic.operations import Operations
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.core import security
from app.database import Base, get_db
from app.models.user import User, UserRole
from app.models.audit_event import AuditEvent
from app.models.support_faq import SupportFAQ
from app.routers import support


class SupportTests(TestCase):
    def setUp(self):
        self.engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
        self.addCleanup(self.engine.dispose)
        Base.metadata.create_all(self.engine, tables=[User.__table__, AuditEvent.__table__, SupportFAQ.__table__])
        self.db = Session(self.engine)
        self.addCleanup(self.db.close)
        self.user = User(id=1, email="synthetic@example.com", phone="56912345678",
            full_name="Test", hashed_password="synthetic-unused", role=UserRole.admin,
            account_roles=["admin"], is_active=True)
        self.db.add(self.user)
        self.db.commit()
        token = (security.create_user_access_token(self.user) if hasattr(security, "create_user_access_token")
                 else security.create_access_token({"sub": "1", "role": "admin"}))
        self.headers = {"Authorization": f"Bearer {token}"}
        app = FastAPI()
        app.include_router(support.router)
        app.dependency_overrides[get_db] = lambda: self.db
        self.client = self.enterContext(TestClient(app, raise_server_exceptions=False))
        self.rate = self.enterContext(patch.object(support, "check_rate_limit"))
        self.payload = dict(slug="test-answer", category="requests", question="Pregunta de prueba?",
            answer="Una respuesta de prueba sin datos personales.", published=True, audience="all", sort_order=0)

    def create(self, **changes):
        return self.client.post("/support/admin/faqs", json={**self.payload, **changes}, headers=self.headers)

    def test_auth_required_everywhere(self):
        for method, path, body in [("get", "/support/faqs", None), ("get", "/support/admin/faqs", None),
            ("post", "/support/admin/faqs", self.payload), ("put", "/support/admin/faqs/1", {**self.payload, "version": 1})]:
            options = {} if body is None else {"json": body}
            self.assertEqual(getattr(self.client, method)(path, **options).status_code, 401)

    def test_client_driver_cannot_read_drafts_or_write(self):
        self.create(published=False)
        for role in [UserRole.client, UserRole.driver]:
            self.user.role = role
            self.db.commit()
            self.assertEqual(self.client.get("/support/admin/faqs", headers=self.headers).status_code, 403)
            self.assertEqual(self.create().status_code, 403)
            self.assertEqual(self.client.put("/support/admin/faqs/1", json={**self.payload, "version": 1}, headers=self.headers).status_code, 403)
            self.assertEqual(self.client.get("/support/faqs?published=true&role=admin", headers=self.headers).json(), [])

    def test_visibility_publication_and_audience(self):
        for audience in ["all", "client", "driver"]:
            self.assertEqual(self.create(slug=f"faq-{audience}", audience=audience).status_code, 201)
        self.create(slug="draft-entry", published=False)
        self.assertEqual(len(self.client.get("/support/admin/faqs", headers=self.headers).json()), 4)
        for role in [UserRole.client, UserRole.driver]:
            self.user.role = role
            self.db.commit()
            data = self.client.get("/support/faqs", headers=self.headers).json()
            self.assertEqual({e["audience"] for e in data}, {"all", role.value})

    def test_update_version_conflict_unpublish_and_audit(self):
        response = self.create()
        self.assertEqual(response.status_code, 201)
        entry = response.json()
        url = f'/support/admin/faqs/{entry["id"]}'
        payload = {**self.payload, "answer": "Respuesta corregida por administrador.", "version": 1, "published": False}
        self.assertEqual(self.client.put(url, json=payload, headers=self.headers).json()["version"], 2)
        self.assertEqual(self.client.put(url, json=payload, headers=self.headers).status_code, 409)
        self.assertEqual(self.client.get("/support/faqs", headers=self.headers).json(), [])
        events = self.db.query(AuditEvent).all()
        self.assertEqual(len(events), 2)
        self.assertEqual(events[-1].before_data["answer"], self.payload["answer"])
        self.assertEqual(events[-1].after_data["answer"], payload["answer"])

    def test_validation_rejects_html_overflow_unknown_fields_and_controls(self):
        for changes in [dict(answer="<script>alert(1)</script>"), dict(question="x\r\nbcc:someone"),
            dict(answer="x" * 4001), dict(category="anything"), dict(user_id=999), dict(audience="admin")]:
            self.assertEqual(self.create(**changes).status_code, 422)
        self.assertEqual(self.db.query(SupportFAQ).count(), 0)

    def test_parameterized_sql_and_duplicate_conflict(self):
        question = "Why '); DROP TABLE users; -- ?"
        self.assertEqual(self.create(question=question).status_code, 201)
        self.assertEqual(self.create().status_code, 409)
        self.assertEqual(self.db.query(User).count(), 1)
        self.assertEqual(self.db.query(SupportFAQ).one().question, question)

    def test_limit_and_rate_limit_enforced(self):
        self.assertEqual(self.client.get("/support/faqs?limit=101", headers=self.headers).status_code, 422)
        self.assertEqual(self.client.get("/support/faqs?offset=-1", headers=self.headers).status_code, 422)
        self.rate.side_effect = HTTPException(429, "Demasiados intentos")
        self.assertEqual(self.create().status_code, 429)
        self.assertEqual(self.client.get("/support/faqs", headers=self.headers).status_code, 429)

    def test_inactive_user_cannot_read(self):
        self.user.is_active = False
        self.db.commit()
        self.assertEqual(self.client.get("/support/faqs", headers=self.headers).status_code, 401)


class SupportMigrationTests(TestCase):
    def test_migration_creates_and_seeds_without_touching_other_tables(self):
        path = Path(__file__).parents[1] / "alembic/versions/b2e4f6a81047_support_faqs.py"
        spec = importlib.util.spec_from_file_location("support_migration", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        engine = create_engine("sqlite://")
        self.addCleanup(engine.dispose)
        with engine.begin() as connection:
            connection.execute(text("CREATE TABLE sentinel (value INTEGER)"))
            connection.execute(text("INSERT INTO sentinel VALUES (42)"))
            with Operations.context(MigrationContext.configure(connection)):
                module.upgrade()
            self.assertEqual(connection.execute(text("SELECT count(*) FROM support_faqs")).scalar(), 7)
            self.assertEqual(connection.execute(text("SELECT value FROM sentinel")).scalar(), 42)
