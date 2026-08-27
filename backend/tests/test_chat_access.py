import os
import unittest

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "1440")
os.environ.setdefault("DATABASE_URL", "postgresql://postgres:postgres@localhost/muvv_test")
os.environ.setdefault("SECRET_KEY", "test-secret-key")

from fastapi import HTTPException

from app.models.driver import Driver
from app.models.freight import FreightRequest, FreightStatus
from app.models.user import User, UserRole
from app.schemas.chat import AdminChatReviewRequest, ChatImageCreate, ChatMessageCreate
from app.services.storage_service import (
    create_chat_image_view_token,
    decode_chat_image_view_token,
)
from app.services.chat_service import require_writable_chat, resolve_freight_chat_access


class FreightChatAccessTests(unittest.TestCase):
    def setUp(self):
        self.client = User(id=11, full_name="Cliente Demo", role=UserRole.client)
        self.driver_user = User(id=22, full_name="Conductor Demo", role=UserRole.driver)
        self.driver = Driver(id=7, user_id=self.driver_user.id)
        self.driver.user = self.driver_user
        self.freight = FreightRequest(
            id=14,
            client_id=self.client.id,
            driver_id=self.driver.id,
            status=FreightStatus.accepted,
        )
        self.freight.client = self.client
        self.freight.driver = self.driver

    def test_only_assigned_client_and_driver_can_open_active_chat(self):
        client_access = resolve_freight_chat_access(None, self.freight, self.client)
        driver_access = resolve_freight_chat_access(None, self.freight, self.driver_user)

        self.assertTrue(client_access.is_writable)
        self.assertEqual(client_access.peer_user_id, self.driver_user.id)
        self.assertTrue(driver_access.is_writable)
        self.assertEqual(driver_access.peer_user_id, self.client.id)

    def test_chat_requires_an_assigned_driver(self):
        self.freight.driver_id = None
        self.freight.driver = None
        with self.assertRaises(HTTPException) as error:
            resolve_freight_chat_access(None, self.freight, self.client)
        self.assertEqual(error.exception.status_code, 409)

    def test_other_users_and_admin_cannot_open_chat(self):
        for user in (
            User(id=33, full_name="Otro cliente", role=UserRole.client),
            User(id=44, full_name="Administrador", role=UserRole.admin),
            User(id=55, full_name="Otro conductor", role=UserRole.driver),
        ):
            with self.subTest(user_id=user.id), self.assertRaises(HTTPException) as error:
                resolve_freight_chat_access(None, self.freight, user)
            self.assertEqual(error.exception.status_code, 403)

    def test_completed_chat_is_read_only(self):
        self.freight.status = FreightStatus.completed
        access = resolve_freight_chat_access(None, self.freight, self.client)

        self.assertFalse(access.is_writable)
        with self.assertRaises(HTTPException) as error:
            require_writable_chat(access)
        self.assertEqual(error.exception.status_code, 409)

    def test_cancelled_chat_is_read_only_for_its_participants(self):
        self.freight.status = FreightStatus.cancelled
        access = resolve_freight_chat_access(None, self.freight, self.driver_user)
        self.assertFalse(access.is_writable)

    def test_chat_message_rejects_blank_or_oversized_payloads(self):
        with self.assertRaises(ValueError):
            ChatMessageCreate.model_validate({"message_text": "   "})
        with self.assertRaises(ValueError):
            ChatMessageCreate.model_validate({"message_text": "x" * 1001})

    def test_chat_image_caption_is_optional_but_validated(self):
        self.assertEqual(ChatImageCreate().caption, "")
        with self.assertRaises(ValueError):
            ChatImageCreate.model_validate({"caption": "foto\x00invalida"})
        with self.assertRaises(ValueError):
            ChatImageCreate.model_validate({"caption": "x" * 1001})

    def test_admin_chat_review_requires_a_meaningful_reason(self):
        with self.assertRaises(ValueError):
            AdminChatReviewRequest.model_validate({"reason": "muy corta"})
        with self.assertRaises(ValueError):
            AdminChatReviewRequest.model_validate({"reason": "revision\x00invalida suficiente"})
        review = AdminChatReviewRequest.model_validate(
            {"reason": "Revision de cumplimiento por posible desintermediacion"}
        )
        self.assertTrue(review.reason.startswith("Revision"))

    def test_chat_image_view_token_is_bound_to_its_message_and_attachment(self):
        token, _ = create_chat_image_view_token(
            freight_id=14,
            message_id=91,
            attachment_ref="freights/14/chat/private.jpg",
        )
        payload = decode_chat_image_view_token(token)
        self.assertEqual(payload["freight_id"], 14)
        self.assertEqual(payload["message_id"], 91)
        self.assertEqual(payload["attachment_ref"], "freights/14/chat/private.jpg")


if __name__ == "__main__":
    unittest.main()
