import httpx
from app.core.config import settings

async def send_push_notification(fcm_token: str, title: str, body: str, data: dict = {}):
    if not settings.FIREBASE_SERVER_KEY or not fcm_token:
        return
    async with httpx.AsyncClient() as client:
        await client.post(
            "https://fcm.googleapis.com/fcm/send",
            headers={
                "Authorization": f"key={settings.FIREBASE_SERVER_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "to": fcm_token,
                "notification": {"title": title, "body": body},
                "data": data,
            },
        )