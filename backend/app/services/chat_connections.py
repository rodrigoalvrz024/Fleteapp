from collections import defaultdict

from fastapi import WebSocket


class FreightChatConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[int, dict[WebSocket, int]] = defaultdict(dict)

    def add(self, freight_id: int, user_id: int, websocket: WebSocket) -> None:
        # A WebSocket is the key, so reconnecting a user does not overwrite another tab.
        self._connections[freight_id][websocket] = user_id

    def remove(self, freight_id: int, websocket: WebSocket) -> None:
        connections = self._connections.get(freight_id)
        if not connections:
            return
        connections.pop(websocket, None)
        if not connections:
            self._connections.pop(freight_id, None)

    def has_active_user(self, freight_id: int, user_id: int) -> bool:
        return user_id in self._connections.get(freight_id, {}).values()

    async def broadcast(self, freight_id: int, payload: dict) -> None:
        stale: list[WebSocket] = []
        for websocket in tuple(self._connections.get(freight_id, ())):
            try:
                await websocket.send_json(payload)
            except Exception:
                stale.append(websocket)
        for websocket in stale:
            self.remove(freight_id, websocket)


freight_chat_connections = FreightChatConnectionManager()
