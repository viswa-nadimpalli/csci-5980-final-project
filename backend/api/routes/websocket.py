from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter(tags=["websocket"])


class ConnectionManager:
    def __init__(self):
        self.pack_connections: dict[str, list[WebSocket]] = {}

    async def connect(self, pack_id: str, websocket: WebSocket):
        await websocket.accept()
        self.pack_connections.setdefault(pack_id, []).append(websocket)

    def disconnect(self, pack_id: str, websocket: WebSocket):
        if pack_id in self.pack_connections:
            self.pack_connections[pack_id] = [
                ws for ws in self.pack_connections[pack_id] if ws != websocket
            ]
            if not self.pack_connections[pack_id]:
                del self.pack_connections[pack_id]

    async def broadcast_to_pack(self, pack_id: str, message: dict):
        if pack_id not in self.pack_connections:
            return

        dead: list[WebSocket] = []
        for ws in self.pack_connections[pack_id]:
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(ws)

        for ws in dead:
            self.disconnect(pack_id, ws)


manager = ConnectionManager()


@router.websocket("/ws/packs/{pack_id}")
async def websocket_pack(pack_id: str, websocket: WebSocket):
    await manager.connect(pack_id, websocket)
    try:
        while True:
            # Keep connection alive; we only push from server side
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(pack_id, websocket)
