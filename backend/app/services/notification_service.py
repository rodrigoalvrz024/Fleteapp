import json
import os
from pathlib import Path

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
    FIREBASE_AVAILABLE = True
except ImportError:
    FIREBASE_AVAILABLE = False


def _init_firebase() -> bool:
    """
    Inicializa Firebase Admin SDK.
    - Producción (Railway): lee desde variable de entorno FIREBASE_CREDENTIALS_JSON
    - Desarrollo local: lee desde archivo firebase-credentials.json
    """
    if not FIREBASE_AVAILABLE:
        return False

    if firebase_admin._apps:
        return True

    # ── Producción: variable de entorno ──────────────────────────
    creds_json = os.environ.get("FIREBASE_CREDENTIALS_JSON")
    if creds_json:
        try:
            cred_dict = json.loads(creds_json)
            cred = credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)
            print("Firebase inicializado desde variable de entorno")
            return True
        except Exception as e:
            print(f"Error inicializando Firebase desde entorno: {e}")
            return False

    # ── Desarrollo local: archivo JSON ───────────────────────────
    cred_path = Path(__file__).parent.parent.parent / "firebase-credentials.json"
    if cred_path.exists():
        try:
            cred = credentials.Certificate(str(cred_path))
            firebase_admin.initialize_app(cred)
            print("Firebase inicializado desde archivo local")
            return True
        except Exception as e:
            print(f"Error inicializando Firebase desde archivo: {e}")
            return False

    print("Firebase: no se encontraron credenciales — notificaciones desactivadas")
    return False


async def send_push_notification(
    fcm_token: str,
    title: str,
    body: str,
    data: dict = {}
) -> str | None:
    """Envía notificación push a un dispositivo específico."""
    if not fcm_token:
        return None

    if not _init_firebase():
        print("Firebase no disponible — notificación no enviada")
        return None

    try:
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data={k: str(v) for k, v in data.items()},
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
                    aps=messaging.Aps(
                        sound="default",
                        badge=1,
                    )
                )
            ),
        )
        response = messaging.send(message)
        print(f"Notificación enviada correctamente: {response}")
        return response
    except Exception as e:
        print(f"Error enviando notificación push: {e}")
        return None


async def send_notification_to_drivers(
    db,
    title: str,
    body: str,
    data: dict = {}
) -> None:
    """Envía notificación a todos los conductores disponibles y aprobados."""
    from app.models.driver import Driver, DriverStatus
    from app.models.user import User

    drivers = db.query(Driver).filter(
        Driver.status == DriverStatus.approved,
        Driver.is_available == True
    ).all()

    sent = 0
    for driver in drivers:
        user = db.query(User).filter(User.id == driver.user_id).first()
        if user and user.fcm_token:
            await send_push_notification(
                fcm_token=user.fcm_token,
                title=title,
                body=body,
                data=data
            )
            sent += 1

    print(f"Notificaciones enviadas a {sent} conductores")


async def send_notification_to_user(
    db,
    user_id: int,
    title: str,
    body: str,
    data: dict = {}
) -> None:
    """Envía notificación a un usuario específico por su ID."""
    from app.models.user import User

    user = db.query(User).filter(User.id == user_id).first()
    if user and user.fcm_token:
        await send_push_notification(
            fcm_token=user.fcm_token,
            title=title,
            body=body,
            data=data
        )
    else:
        print(f"Usuario {user_id} no tiene FCM token registrado")