import json

from app.core.config import settings

try:
    import firebase_admin
    from firebase_admin import credentials, messaging

    FIREBASE_AVAILABLE = True
except ImportError:
    FIREBASE_AVAILABLE = False


def _init_firebase() -> bool:
    """Initialize Firebase Admin only from the backend environment."""
    if not FIREBASE_AVAILABLE or firebase_admin._apps:
        return FIREBASE_AVAILABLE

    credentials_json = settings.FIREBASE_CREDENTIALS_JSON.strip()
    if not credentials_json:
        return False

    try:
        firebase_admin.initialize_app(
            credentials.Certificate(json.loads(credentials_json))
        )
        return True
    except Exception:
        # Credential details and provider errors can contain sensitive fields.
        print("[notifications] Firebase initialization failed")
        return False


async def send_push_notification(
    fcm_token: str,
    title: str,
    body: str,
    data: dict | None = None,
) -> str | None:
    if not fcm_token or not _init_firebase():
        return None

    try:
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={key: str(value) for key, value in (data or {}).items()},
            token=fcm_token,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    sound="default",
                    click_action="FLUTTER_NOTIFICATION_CLICK",
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default", badge=1)
                )
            ),
        )
        return messaging.send(message)
    except Exception:
        print("[notifications] Push delivery failed")
        return None


async def send_notification_to_drivers(
    db,
    title: str,
    body: str,
    data: dict | None = None,
    freight=None,
) -> int:
    from app.models.driver import Driver, DriverStatus
    from app.models.user import User
    from app.services.freight_matching_service import driver_matches_freight

    drivers = (
        db.query(Driver)
        .filter(
            Driver.status == DriverStatus.approved,
            Driver.is_available == True,  # noqa: E712
        )
        .all()
    )

    sent = 0
    for driver in drivers:
        if freight is not None and not driver_matches_freight(driver, freight):
            continue
        user = db.query(User).filter(User.id == driver.user_id).first()
        if user and user.fcm_token:
            if await send_push_notification(user.fcm_token, title, body, data):
                sent += 1
    return sent


async def send_notification_to_user(
    db,
    user_id: int,
    title: str,
    body: str,
    data: dict | None = None,
) -> None:
    from app.models.user import User

    user = db.query(User).filter(User.id == user_id).first()
    if user and user.fcm_token:
        await send_push_notification(user.fcm_token, title, body, data)
