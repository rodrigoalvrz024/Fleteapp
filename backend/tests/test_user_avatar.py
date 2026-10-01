import base64
import io
import os
from unittest import IsolatedAsyncioTestCase, TestCase
from unittest.mock import AsyncMock, patch

os.environ.setdefault('APP_ENV', 'test')
os.environ.setdefault('DATABASE_URL', 'postgresql://localhost/synthetic')
os.environ.setdefault('SECRET_KEY', 'synthetic-avatar-unit-test-key')

from fastapi import FastAPI, HTTPException, UploadFile
from fastapi.testclient import TestClient
from fastapi.responses import Response
from starlette.datastructures import Headers
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool
from app.database import Base, get_db
from app.core import security
from app.models.user import User, UserRole
from app.models.audit_event import AuditEvent
from app.routers import avatars as users
from app.routers import users as profile_routes
from app.services import storage_service as storage

PNG = base64.b64decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
REFERENCE = 'avatars/1/' + 'a' * 32 + '.png'


class AvatarEndpointTests(TestCase):
    def setUp(self):
        engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
        self.addCleanup(engine.dispose)
        Base.metadata.create_all(engine, tables=[Base.metadata.tables[name] for name in (
            'users', 'user_consents', 'audit_events', 'data_privacy_requests')])
        self.db = Session(engine, autoflush=False)
        self.addCleanup(self.db.close)
        self.user = User(id=1, email='synthetic@example.com', phone='56912345678',
            full_name='Synthetic Client', hashed_password='unused-synthetic-hash',
            role=UserRole.client, account_roles=['client'], is_active=True)
        self.db.add(self.user)
        self.db.commit()
        token = (security.create_user_access_token(self.user)
                 if hasattr(security, 'create_user_access_token') else
                 security.create_access_token({'sub': '1', 'role': 'client'}))
        self.headers = {'Authorization': f'Bearer {token}'}
        app = FastAPI()
        app.include_router(profile_routes.router)
        app.include_router(users.router)
        app.add_middleware(users.AvatarBodyLimitMiddleware)
        app.dependency_overrides[get_db] = lambda: self.db
        self.client = self.enterContext(TestClient(app, raise_server_exceptions=False))
        self.upload = self.enterContext(patch.object(users, 'upload_user_avatar',
            new=AsyncMock(return_value=REFERENCE)))
        self.limit = self.enterContext(patch.object(users, 'check_rate_limit'))
        self.delete = self.enterContext(patch.object(users, 'delete_private_document'))

    def send_photo(self, headers=None):
        return self.client.post('/users/me/avatar', headers=headers or self.headers,
                                files={'file': ('photo.png', PNG, 'image/png')})

    def test_photo_survives_new_get_me_and_roles_are_preserved(self):
        for role in (UserRole.client, UserRole.driver, UserRole.admin):
            with self.subTest(role=role):
                self.user.role = role
                self.db.commit()
                response = self.send_photo()
                self.assertEqual(response.status_code, 200, response.text)
                self.assertEqual(response.json()['avatar_url'], REFERENCE)
                self.assertEqual(response.json()['role'], role.value)
                self.assertEqual(self.client.get('/users/me', headers=self.headers).json()['avatar_url'], REFERENCE)
        self.limit.assert_called_with(self.limit.call_args.args[0], scope='user-avatar-upload',
            identifier='1', max_attempts=10, window_seconds=3600)
        self.assertEqual(self.db.query(AuditEvent).first().after_data, {'has_avatar': True})

    def test_unauthenticated_cannot_upload_or_view(self):
        self.assertEqual(self.send_photo({'X-Test': 'anonymous'}).status_code, 401)
        self.assertEqual(self.client.get('/users/me/avatar').status_code, 401)
        self.upload.assert_not_called()

    def test_reader_uses_only_own_validated_reference(self):
        self.user.avatar_url = REFERENCE
        self.db.commit()
        with patch.object(users, 'stream_private_document', return_value=Response(PNG, media_type='image/png')) as stream:
            response = self.client.get('/users/me/avatar?user_id=2&path=drivers/2/license_image/x', headers=self.headers)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.content, PNG)
            stream.assert_called_once_with(REFERENCE)
            for ref in ('avatars/2/' + 'a' * 32 + '.png', 'https://example.com/private', 'avatars/1/../secret'):
                self.user.avatar_url = ref
                self.db.commit()
                self.assertEqual(self.client.get('/users/me/avatar', headers=self.headers).status_code, 404)

    def test_upload_failure_does_not_change_existing_photo(self):
        self.user.avatar_url = REFERENCE
        self.db.commit()
        self.upload.side_effect = HTTPException(503, 'No fue posible guardar el archivo.')
        self.assertEqual(self.send_photo().status_code, 503)
        self.db.refresh(self.user)
        self.assertEqual(self.user.avatar_url, REFERENCE)
        self.delete.assert_not_called()

    def test_stale_session_during_upload_cannot_attach(self):
        with patch.object(users, '_lock_avatar_user', side_effect=HTTPException(401, 'Sesion no disponible')):
            self.assertEqual(self.send_photo().status_code, 401)
        self.assertIsNone(self.user.avatar_url)

    def test_response_failure_rolls_back_photo(self):
        with patch.object(users, '_user_response_with_legal_status', side_effect=ValueError('PRIVATE')):
            response = self.send_photo()
        self.assertEqual(response.status_code, 500)
        self.assertNotIn('PRIVATE', response.text)
        self.assertIsNone(self.user.avatar_url)
        self.assertEqual(self.db.query(AuditEvent).count(), 0)

    def test_rate_limit_stops_storage_upload(self):
        self.limit.side_effect = HTTPException(429, 'Demasiados intentos.')
        self.assertEqual(self.send_photo().status_code, 429)
        self.upload.assert_not_called()

    def test_body_limit_rejects_before_upload(self):
        response = self.client.post('/users/me/avatar', headers={
            **self.headers, 'Content-Length': str(7 * 1024 * 1024)}, content=b'x')
        self.assertEqual(response.status_code, 413)
        self.upload.assert_not_called()

    def test_lock_rechecks_password_and_account_status(self):
        original_hash = self.user.hashed_password
        generation = getattr(self.user, 'session_version', None)
        for field, value in [('hashed_password', 'changed'), ('is_active', False)]:
            old = getattr(self.user, field)
            setattr(self.user, field, value)
            self.db.commit()
            with self.assertRaises(HTTPException) as error:
                users._lock_avatar_user(self.db, self.user.id, original_hash, generation)
            self.assertEqual(error.exception.status_code, 401)
            setattr(self.user, field, old)
            self.db.commit()

    def test_cleanup_failure_does_not_report_false_save_failure(self):
        self.user.avatar_url = 'avatars/1/' + 'b' * 32 + '.jpg'
        self.db.commit()
        self.delete.side_effect = RuntimeError('private storage error')
        self.assertEqual(self.send_photo().status_code, 200)
        self.assertEqual(self.user.avatar_url, REFERENCE)


class AvatarStorageTests(IsolatedAsyncioTestCase):
    def file(self, content, kind='image/png', name='photo.png'):
        return UploadFile(io.BytesIO(content), filename=name, headers=Headers({'content-type': kind}))

    async def test_private_path_ignores_filename(self):
        with patch.object(storage, '_ensure_storage_configured'), patch.object(storage, '_upload_private_object') as upload:
            reference = await storage.upload_user_avatar(self.file(PNG, name='../../secret.png'), 17)
        self.assertTrue(storage.is_user_avatar_ref(reference, 17))
        self.assertFalse(storage.is_user_avatar_ref(reference, 1))
        self.assertEqual(upload.call_args.args[2], 'image/png')

    async def test_rejects_oversize_svg_pdf_empty_and_spoofed_images(self):
        for content, kind in ((b'x' * (5 * 1024 * 1024 + 1), 'image/png'),
                              (b'<svg/>', 'image/svg+xml'), (b'%PDF-1.7', 'application/pdf'),
                              (b'', 'image/png'), (b'<script/>', 'image/jpeg')):
            with self.subTest(kind=kind), patch.object(storage, '_upload_private_object') as upload:
                with self.assertRaises(HTTPException) as error:
                    await storage.upload_user_avatar(self.file(content, kind), 1)
                self.assertEqual(error.exception.status_code, 400)
                upload.assert_not_called()
