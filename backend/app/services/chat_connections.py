import asyncio
from collections import defaultdict
from collections.abc import Awaitable, Callable
from dataclasses import dataclass

from fastapi import WebSocket


CHAT_SEND_TIMEOUT_SECONDS = 3.0
CHAT_CLOSE_TIMEOUT_SECONDS = 0.5


@dataclass(frozen=True)
class ChatConnection:
    user_id: int
    authorize: Callable[[], Awaitable[bool]]


class FreightChatConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[int, dict[WebSocket, ChatConnection]] = defaultdict(dict)
        self._closing: dict[WebSocket, asyncio.Task] = {}

    def add(self, freight_id: int, user_id: int, websocket: WebSocket,
            authorize: Callable[[], Awaitable[bool]]) -> None:
        # A WebSocket is the key, so reconnecting a user does not overwrite another tab.
        self._connections[freight_id][websocket] = ChatConnection(user_id, authorize)

    def remove(self, freight_id: int, websocket: WebSocket) -> None:
        connections = self._connections.get(freight_id)
        if not connections:
            return
        connections.pop(websocket, None)
        if not connections:
            self._connections.pop(freight_id, None)

    def has_active_user(self, freight_id: int, user_id: int) -> bool:
        return any(connection.user_id == user_id
                   for connection in self._connections.get(freight_id, {}).values())

    async def _disconnect(self, freight_id: int, websocket: WebSocket) -> None:
        # Stop considering this peer for delivery/notification before closing it.
        self.remove(freight_id, websocket)
        task = self._closing.get(websocket)
        if task is None:
            task = asyncio.create_task(websocket.close(code=1013))
            self._closing[websocket] = task

            def finished(done: asyncio.Task) -> None:
                self._closing.pop(websocket, None)
                if not done.cancelled():
                    done.exception()

            task.add_done_callback(finished)
        # Transport close may absorb cancellation while finishing TCP cleanup.
        # Keep it supervised, but do not wait for that cleanup in the broadcast.
        await asyncio.wait({task}, timeout=CHAT_CLOSE_TIMEOUT_SECONDS)

    async def broadcast(self, freight_id: int, payload: dict) -> None:
        for websocket, connection in tuple(self._connections.get(freight_id, {}).items()):
            if self._connections.get(freight_id, {}).get(websocket) is not connection:
                continue
            try:
                # An open socket is not proof that access is still valid.
                if not await connection.authorize():
                    self.remove(freight_id, websocket)
                    continue
                if self._connections.get(freight_id, {}).get(websocket) is not connection:
                    continue
                await asyncio.wait_for(websocket.send_json(payload), CHAT_SEND_TIMEOUT_SECONDS)
            except asyncio.CancelledError:
                # A cancelled send may be partial; do not reuse that connection.
                await self._disconnect(freight_id, websocket)
                raise
            except Exception:
                await self._disconnect(freight_id, websocket)


freight_chat_connections = FreightChatConnectionManager()
