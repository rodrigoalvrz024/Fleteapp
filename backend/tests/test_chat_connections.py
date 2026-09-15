import asyncio
import unittest
from unittest.mock import AsyncMock, patch

from app.services.chat_connections import FreightChatConnectionManager


class ChatConnectionTests(unittest.IsolatedAsyncioTestCase):
    async def test_stalled_send_is_cancelled_and_other_recipient_receives(self):
        manager = FreightChatConnectionManager()
        stalled, allowed = AsyncMock(), AsyncMock()
        cancelled = asyncio.Event()

        async def blocked_send(_):
            try:
                await asyncio.Event().wait()
            finally:
                cancelled.set()

        stalled.send_json.side_effect = blocked_send
        manager.add(1, 10, stalled, AsyncMock(return_value=True))
        manager.add(1, 20, allowed, AsyncMock(return_value=True))
        with patch("app.services.chat_connections.CHAT_SEND_TIMEOUT_SECONDS", 0.01):
            await asyncio.wait_for(manager.broadcast(1, {"type": "test"}), timeout=1)
        self.assertTrue(cancelled.is_set())
        self.assertFalse(manager.has_active_user(1, 10))
        allowed.send_json.assert_awaited_once_with({"type": "test"})
        stalled.close.assert_awaited_once_with(code=1013)

    async def test_stalled_close_does_not_block_other_recipient(self):
        manager = FreightChatConnectionManager()
        broken, allowed = AsyncMock(), AsyncMock()
        closed = asyncio.Event()
        release = asyncio.Event()
        broken.send_json.side_effect = RuntimeError("synthetic transport failure")

        async def blocked_close(**_):
            try:
                await release.wait()
            finally:
                closed.set()

        broken.close.side_effect = blocked_close
        manager.add(1, 10, broken, AsyncMock(return_value=True))
        manager.add(1, 20, allowed, AsyncMock(return_value=True))
        try:
            with patch("app.services.chat_connections.CHAT_CLOSE_TIMEOUT_SECONDS", 0.01):
                await asyncio.wait_for(manager.broadcast(1, {"type": "test"}), timeout=1)
            self.assertFalse(closed.is_set())
            self.assertFalse(manager.has_active_user(1, 10))
            allowed.send_json.assert_awaited_once()
            self.assertIn(broken, manager._closing)
        finally:
            release.set()
            await asyncio.wait_for(asyncio.gather(*manager._closing.values()), timeout=1)
        self.assertTrue(closed.is_set())
        self.assertFalse(manager._closing)

    async def test_close_that_absorbs_cancellation_does_not_delay_broadcast(self):
        manager = FreightChatConnectionManager()
        broken, allowed = AsyncMock(), AsyncMock()
        release, cancelled = asyncio.Event(), asyncio.Event()
        broken.send_json.side_effect = RuntimeError("synthetic transport failure")

        async def stubborn_close(**_):
            try:
                await release.wait()
            except asyncio.CancelledError:
                cancelled.set()
                await release.wait()

        broken.close.side_effect = stubborn_close
        manager.add(1, 10, broken, AsyncMock(return_value=True))
        manager.add(1, 20, allowed, AsyncMock(return_value=True))
        try:
            with patch("app.services.chat_connections.CHAT_CLOSE_TIMEOUT_SECONDS", 0.01):
                await asyncio.wait_for(manager.broadcast(1, {"type": "test"}), timeout=1)
            allowed.send_json.assert_awaited_once()
            self.assertFalse(cancelled.is_set())
            self.assertIn(broken, manager._closing)
        finally:
            release.set()
            await asyncio.wait_for(asyncio.gather(*manager._closing.values()), timeout=1)
        self.assertFalse(manager._closing)

    async def test_cancellation_during_close_keeps_cleanup_supervised(self):
        manager = FreightChatConnectionManager()
        socket = AsyncMock()
        started, release, cancelled = asyncio.Event(), asyncio.Event(), asyncio.Event()
        socket.send_json.side_effect = RuntimeError("synthetic transport failure")

        async def stubborn_close(**_):
            started.set()
            try:
                await release.wait()
            except asyncio.CancelledError:
                cancelled.set()
                await release.wait()

        socket.close.side_effect = stubborn_close
        manager.add(1, 10, socket, AsyncMock(return_value=True))
        task = asyncio.create_task(manager.broadcast(1, {"type": "test"}))
        try:
            await asyncio.wait_for(started.wait(), timeout=1)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await asyncio.wait_for(task, timeout=1)
            self.assertFalse(cancelled.is_set())
            self.assertFalse(manager.has_active_user(1, 10))
            self.assertIn(socket, manager._closing)
        finally:
            release.set()
            await asyncio.wait_for(asyncio.gather(task, *manager._closing.values(),
                                                return_exceptions=True), timeout=1)
        self.assertFalse(manager._closing)

    async def test_failed_close_preserves_healthy_tab_and_reconnect(self):
        manager = FreightChatConnectionManager()
        broken, allowed, replacement = AsyncMock(), AsyncMock(), AsyncMock()
        broken.send_json.side_effect = RuntimeError("synthetic transport failure")
        broken.close.side_effect = RuntimeError("already closed")
        for socket in (broken, allowed):
            manager.add(1, 10, socket, AsyncMock(return_value=True))
        await manager.broadcast(1, {"type": "first"})
        manager.add(1, 10, replacement, AsyncMock(return_value=True))
        await manager.broadcast(1, {"type": "second"})
        self.assertEqual(broken.send_json.await_count, 1)
        self.assertEqual(allowed.send_json.await_count, 2)
        replacement.send_json.assert_awaited_once_with({"type": "second"})
        self.assertTrue(manager.has_active_user(1, 10))

    async def test_removed_connection_in_snapshot_is_not_sent_to(self):
        manager = FreightChatConnectionManager()
        first, removed = AsyncMock(), AsyncMock()

        async def remove_other():
            manager.remove(1, removed)
            return True

        manager.add(1, 10, first, remove_other)
        manager.add(1, 20, removed, AsyncMock(return_value=True))
        await manager.broadcast(1, {"type": "test"})
        first.send_json.assert_awaited_once()
        removed.send_json.assert_not_called()

    async def test_removed_during_authorization_is_not_sent_to(self):
        manager = FreightChatConnectionManager()
        socket = AsyncMock()

        async def remove_self():
            manager.remove(1, socket)
            return True

        manager.add(1, 10, socket, remove_self)
        await manager.broadcast(1, {"type": "test"})
        socket.send_json.assert_not_called()

    async def test_broadcast_cancellation_cleans_partial_send_and_propagates(self):
        manager = FreightChatConnectionManager()
        socket, next_socket = AsyncMock(), AsyncMock()
        started, stopped = asyncio.Event(), asyncio.Event()

        async def blocked_send(_):
            started.set()
            try:
                await asyncio.Event().wait()
            finally:
                stopped.set()

        socket.send_json.side_effect = blocked_send
        manager.add(1, 10, socket, AsyncMock(return_value=True))
        manager.add(1, 20, next_socket, AsyncMock(return_value=True))
        task = asyncio.create_task(manager.broadcast(1, {"type": "test"}))
        try:
            await asyncio.wait_for(started.wait(), timeout=1)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await asyncio.wait_for(task, timeout=1)
        finally:
            if not task.done():
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
        self.assertTrue(stopped.is_set())
        self.assertFalse(manager.has_active_user(1, 10))
        self.assertTrue(manager.has_active_user(1, 20))
        socket.close.assert_awaited_once_with(code=1013)
        next_socket.send_json.assert_not_called()

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
