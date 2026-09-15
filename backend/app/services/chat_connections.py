from collections import defaultdict
from collections.abc import Awaitable, Callable
from dataclasses import dataclass

from fastapi import WebSocket


@dataclass(frozen=True)
class ChatConnection:
    user_id: int
    authorize: Callable[[], Awaitable[bool]]


class FreightChatConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[int, dict[WebSocket, ChatConnection]] = defaultdict(dict)

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

    async def broadcast(self, freight_id: int, payload: dict) -> None:
        stale: list[WebSocket] = []
        for websocket, connection in tuple(self._connections.get(freight_id, {}).items()):
            try:
                # An open socket is not proof that access is still valid.
                if not await connection.authorize():
                    stale.append(websocket)
                    continue
                await websocket.send_json(payload)
            except Exception:
                stale.append(websocket)
        for websocket in stale:
            self.remove(freight_id, websocket)


freight_chat_connections = FreightChatConnectionManager()
