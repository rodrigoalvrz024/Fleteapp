import unittest
from unittest.mock import AsyncMock

from app.services.chat_connections import FreightChatConnectionManager


class ChatConnectionTests(unittest.IsolatedAsyncioTestCase):
    async def test_every_delivery_revalidates_access_and_removes_denied_socket(self):
        manager = FreightChatConnectionManager()
        denied, allowed = AsyncMock(), AsyncMock()
        check = AsyncMock(side_effect=[True, False])
        manager.add(1, 10, denied, check)
        manager.add(1, 20, allowed, AsyncMock(return_value=True))
        await manager.broadcast(1, {"type": "first"})
        await manager.broadcast(1, {"type": "second"})
        self.assertEqual(check.await_count, 2)
        denied.send_json.assert_awaited_once_with({"type": "first"})
        self.assertEqual(allowed.send_json.await_count, 2)
        self.assertFalse(manager.has_active_user(1, 10))
        self.assertTrue(manager.has_active_user(1, 20))

    async def test_authorization_failure_never_delivers_and_other_tabs_continue(self):
        manager = FreightChatConnectionManager()
        broken, allowed = AsyncMock(), AsyncMock()
        manager.add(1, 10, broken, AsyncMock(side_effect=RuntimeError("synthetic failure")))
        manager.add(1, 10, allowed, AsyncMock(return_value=True))
        await manager.broadcast(1, {"type": "test"})
        broken.send_json.assert_not_called()
        allowed.send_json.assert_awaited_once()
        self.assertTrue(manager.has_active_user(1, 10))
        manager.remove(1, allowed)
        self.assertFalse(manager.has_active_user(1, 10))
