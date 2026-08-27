import asyncio
import logging
from datetime import datetime, timezone

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    Request,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from pydantic import ValidationError
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from app.core.config import settings
from app.core.rate_limit import check_rate_limit
from app.core.security import decode_token, get_current_user, require_role
from app.database import SessionLocal, get_db
from app.models.freight import FreightRequest
from app.models.freight_chat import FreightChatMessage
from app.models.user import User
from app.schemas.chat import (
    AdminChatReviewRequest,
    AdminChatReviewResponse,
    ChatMessageCreate,
    ChatImageCreate,
    ChatMessageResponse,
    ChatPeerResponse,
    ChatReadResponse,
    ChatSummaryResponse,
)
from app.services.audit_service import record_audit_event
from app.services.chat_connections import freight_chat_connections
from app.services.chat_service import require_writable_chat, resolve_freight_chat_access
from app.services.storage_service import (
    create_chat_image_view_token,
    decode_chat_image_view_token,
    delete_private_document,
    stream_private_document,
    upload_freight_chat_image,
)


router = APIRouter(prefix="/freights", tags=["Chat"])
logger = logging.getLogger(__name__)


def _freight_for_chat(db: Session, freight_id: int) -> FreightRequest:
    freight = (
        db.query(FreightRequest)
        .options(
            joinedload(FreightRequest.client),
            joinedload(FreightRequest.driver),
        )
        .filter(FreightRequest.id == freight_id)
        .first()
    )
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    return freight


def _chat_image_view_path(message: FreightChatMessage) -> str | None:
    if message.message_type != "image" or not message.attachment_ref:
        return None
    token, _ = create_chat_image_view_token(
        message.freight_id,
        message.id,
        message.attachment_ref,
    )
    return f"/freights/chat/images/{token}"


def _chat_message_response(message: FreightChatMessage) -> ChatMessageResponse:
    return ChatMessageResponse.model_validate(message).model_copy(
        update={"attachment_view_path": _chat_image_view_path(message)}
    )


@router.post(
    "/{freight_id}/chat/admin-review",
    response_model=AdminChatReviewResponse,
)
def review_chat_for_compliance(
    freight_id: int,
    data: AdminChatReviewRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_admin: User = Depends(require_role("admin")),
):
    """Return a read-only recent conversation for a documented CEO review.

    This endpoint deliberately does not reuse the participant chat access path:
    administrators cannot send, mark as read, subscribe to, or otherwise alter a
    private conversation. Every review has a reason and leaves an audit record.
    """

    check_rate_limit(
        request,
        scope="freight-chat-admin-review",
        identifier=str(current_admin.id),
        max_attempts=settings.CHAT_ADMIN_REVIEW_MAX_PER_HOUR,
        window_seconds=60 * 60,
    )
    freight = _freight_for_chat(db, freight_id)
    driver = freight.driver
    if not driver:
        raise HTTPException(
            status_code=409,
            detail="No hay una conversacion disponible hasta asignar un conductor",
        )
    driver_user = driver.user or db.query(User).filter(User.id == driver.user_id).first()
    if not driver_user:
        raise HTTPException(status_code=409, detail="El conductor asignado no esta disponible")

    query = (
        db.query(FreightChatMessage)
        .filter(FreightChatMessage.freight_id == freight.id)
        .order_by(FreightChatMessage.id.desc())
    )
    message_limit = settings.CHAT_ADMIN_REVIEW_MESSAGE_LIMIT
    recent_messages = query.limit(message_limit + 1).all()
    has_more = len(recent_messages) > message_limit
    recent_messages = list(reversed(recent_messages[:message_limit]))

    record_audit_event(
        db,
        actor=current_admin,
        entity_type="freight_chat",
        entity_id=freight.id,
        event_type="freight.chat_review_opened",
        reason=data.reason,
        request=request,
        metadata={
            "message_count": len(recent_messages),
            "image_count": sum(message.message_type == "image" for message in recent_messages),
            "has_more": has_more,
            "read_only": True,
        },
    )
    db.commit()

    status = freight.status.value if hasattr(freight.status, "value") else str(freight.status)
    return AdminChatReviewResponse(
        freight_id=freight.id,
        status=status,
        client_user_id=freight.client_id,
        driver_user_id=driver_user.id,
        client=ChatPeerResponse(
            full_name=freight.client.full_name or "Cliente",
            role="client",
            avatar_url=freight.client.avatar_url,
        ),
        driver=ChatPeerResponse(
            full_name=driver_user.full_name or "Conductor",
            role="driver",
            avatar_url=driver_user.avatar_url,
        ),
        messages=[_chat_message_response(message) for message in recent_messages],
        has_more=has_more,
    )


def _message_event(message: FreightChatMessage) -> dict:
    return {
        "type": "message",
        "message": _chat_message_response(message).model_dump(mode="json"),
    }


async def _notify_chat_recipient(
    *,
    recipient_user_id: int,
    freight_id: int,
    sender_name: str,
    message_type: str,
) -> None:
    """Send a privacy-safe push without exposing chat content on a lock screen."""

    from app.services.notification_service import send_notification_to_user

    db = SessionLocal()
    try:
        await send_notification_to_user(
            db,
            recipient_user_id,
            "Nuevo mensaje de Muvv",
            (
                f"{sender_name} te envio una foto sobre tu flete."
                if message_type == "image"
                else f"{sender_name} te envio un mensaje sobre tu flete."
            ),
            {
                "type": "freight_chat",
                "freight_id": freight_id,
                "route": f"/app/chat/{freight_id}",
            },
        )
    except Exception:
        # Push delivery must never make the trip coordination API fail.
        logger.warning("Chat push delivery failed")
    finally:
        db.close()


@router.get("/{freight_id}/chat/summary", response_model=ChatSummaryResponse)
def get_chat_summary(
    freight_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    freight = _freight_for_chat(db, freight_id)
    access = resolve_freight_chat_access(db, freight, current_user)
    unread_count = (
        db.query(func.count(FreightChatMessage.id))
        .filter(
            FreightChatMessage.freight_id == freight.id,
            FreightChatMessage.receiver_user_id == current_user.id,
            FreightChatMessage.read_at.is_(None),
        )
        .scalar()
        or 0
    )
    status = freight.status.value if hasattr(freight.status, "value") else str(freight.status)
    return ChatSummaryResponse(
        freight_id=freight.id,
        is_writable=access.is_writable,
        status=status,
        unread_count=int(unread_count),
        max_message_length=settings.CHAT_MESSAGE_MAX_LENGTH,
        peer=ChatPeerResponse(
            full_name=access.peer_full_name,
            role=access.peer_role,
            avatar_url=access.peer_avatar_url,
        ),
    )


@router.get("/{freight_id}/chat/messages", response_model=list[ChatMessageResponse])
def list_chat_messages(
    freight_id: int,
    before_id: int | None = Query(default=None, ge=1),
    limit: int = Query(
        default=settings.CHAT_MESSAGE_PAGE_SIZE,
        ge=1,
        le=settings.CHAT_MESSAGE_MAX_PAGE_SIZE,
    ),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    freight = _freight_for_chat(db, freight_id)
    resolve_freight_chat_access(db, freight, current_user)
    query = db.query(FreightChatMessage).filter(FreightChatMessage.freight_id == freight.id)
    if before_id:
        query = query.filter(FreightChatMessage.id < before_id)
    messages = query.order_by(FreightChatMessage.id.desc()).limit(limit).all()
    return [_chat_message_response(message) for message in reversed(messages)]


@router.post("/{freight_id}/chat/messages", response_model=ChatMessageResponse, status_code=201)
async def create_chat_message(
    freight_id: int,
    data: ChatMessageCreate,
    request: Request,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    check_rate_limit(
        request,
        scope="freight-chat-send",
        identifier=f"{current_user.id}:{freight_id}",
        max_attempts=settings.CHAT_SEND_MAX_MESSAGES_PER_MINUTE,
        window_seconds=60,
    )
    freight = _freight_for_chat(db, freight_id)
    access = resolve_freight_chat_access(db, freight, current_user)
    require_writable_chat(access)
    message = FreightChatMessage(
        freight_id=freight.id,
        sender_user_id=current_user.id,
        receiver_user_id=access.peer_user_id,
        message_text=data.message_text,
        message_type=data.message_type,
    )
    db.add(message)
    db.flush()
    db.refresh(message)
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight_chat",
        entity_id=message.id,
        event_type="freight.chat_message_sent",
        request=request,
        metadata={
            "freight_id": freight.id,
            "receiver_user_id": access.peer_user_id,
            "message_type": data.message_type,
            "message_length": len(data.message_text),
        },
    )
    db.commit()
    await freight_chat_connections.broadcast(freight.id, _message_event(message))
    if not freight_chat_connections.has_active_user(freight.id, access.peer_user_id):
        background_tasks.add_task(
            _notify_chat_recipient,
            recipient_user_id=access.peer_user_id,
            freight_id=freight.id,
            sender_name=(current_user.full_name or "Tu contacto").split(" ")[0],
            message_type="text",
        )
    return _chat_message_response(message)


@router.post(
    "/{freight_id}/chat/images",
    response_model=ChatMessageResponse,
    status_code=201,
)
async def create_chat_image(
    freight_id: int,
    request: Request,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    caption: str = Form(default=""),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    check_rate_limit(
        request,
        scope="freight-chat-image-send",
        identifier=f"{current_user.id}:{freight_id}",
        max_attempts=settings.CHAT_IMAGE_SEND_MAX_PER_MINUTE,
        window_seconds=60,
    )
    try:
        validated_caption = ChatImageCreate(caption=caption).caption
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors())

    freight = _freight_for_chat(db, freight_id)
    access = resolve_freight_chat_access(db, freight, current_user)
    require_writable_chat(access)
    uploaded = await upload_freight_chat_image(file, freight.id)

    try:
        message = FreightChatMessage(
            freight_id=freight.id,
            sender_user_id=current_user.id,
            receiver_user_id=access.peer_user_id,
            message_text=validated_caption,
            message_type="image",
            attachment_ref=uploaded.reference,
            attachment_content_type=uploaded.content_type,
            attachment_size_bytes=uploaded.size_bytes,
        )
        db.add(message)
        db.flush()
        db.refresh(message)
        record_audit_event(
            db,
            actor=current_user,
            entity_type="freight_chat",
            entity_id=message.id,
            event_type="freight.chat_image_sent",
            request=request,
            metadata={
                "freight_id": freight.id,
                "receiver_user_id": access.peer_user_id,
                "message_type": "image",
                "content_type": uploaded.content_type,
                "size_bytes": uploaded.size_bytes,
                "has_caption": bool(validated_caption),
            },
        )
        db.commit()
    except Exception:
        db.rollback()
        try:
            delete_private_document(uploaded.reference)
        except Exception:
            logger.warning("Could not clean up failed chat image upload")
        raise

    await freight_chat_connections.broadcast(freight.id, _message_event(message))
    if not freight_chat_connections.has_active_user(freight.id, access.peer_user_id):
        background_tasks.add_task(
            _notify_chat_recipient,
            recipient_user_id=access.peer_user_id,
            freight_id=freight.id,
            sender_name=(current_user.full_name or "Tu contacto").split(" ")[0],
            message_type="image",
        )
    return _chat_message_response(message)


@router.post("/{freight_id}/chat/read", response_model=ChatReadResponse)
async def mark_chat_messages_read(
    freight_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    freight = _freight_for_chat(db, freight_id)
    resolve_freight_chat_access(db, freight, current_user)
    read_at = datetime.now(timezone.utc)
    marked_count = (
        db.query(FreightChatMessage)
        .filter(
            FreightChatMessage.freight_id == freight.id,
            FreightChatMessage.receiver_user_id == current_user.id,
            FreightChatMessage.read_at.is_(None),
        )
        .update({FreightChatMessage.read_at: read_at}, synchronize_session=False)
    )
    if marked_count:
        db.commit()
        await freight_chat_connections.broadcast(
            freight.id,
            {
                "type": "read",
                "reader_user_id": current_user.id,
                "read_at": read_at.isoformat(),
            },
        )
    return ChatReadResponse(marked_count=marked_count)


@router.get("/chat/images/{token}")
def view_chat_image(token: str, db: Session = Depends(get_db)):
    payload = decode_chat_image_view_token(token)
    message = (
        db.query(FreightChatMessage)
        .filter(
            FreightChatMessage.id == payload.get("message_id"),
            FreightChatMessage.freight_id == payload.get("freight_id"),
            FreightChatMessage.message_type == "image",
        )
        .first()
    )
    if not message or message.attachment_ref != payload.get("attachment_ref"):
        raise HTTPException(status_code=404, detail="Imagen no disponible")
    return stream_private_document(message.attachment_ref)


def _websocket_origin_allowed(websocket: WebSocket) -> bool:
    origin = websocket.headers.get("origin", "").rstrip("/")
    # Native clients do not normally send Origin. Browsers must match CORS hosts.
    return not origin or origin in settings.cors_origins


async def _websocket_user(websocket: WebSocket) -> User | None:
    try:
        payload = await asyncio.wait_for(websocket.receive_json(), timeout=8)
    except (asyncio.TimeoutError, WebSocketDisconnect, ValueError, TypeError):
        return None
    if not isinstance(payload, dict) or payload.get("type") != "auth":
        return None
    token = payload.get("token")
    if not isinstance(token, str) or not 20 <= len(token) <= 4096:
        return None
    try:
        claims = decode_token(token)
        user_id = int(claims.get("sub"))
    except (HTTPException, TypeError, ValueError):
        return None
    db = SessionLocal()
    try:
        return db.query(User).filter(User.id == user_id, User.is_active.is_(True)).first()
    finally:
        db.close()


@router.websocket("/{freight_id}/chat/live")
async def freight_chat_live(websocket: WebSocket, freight_id: int):
    if not _websocket_origin_allowed(websocket):
        await websocket.close(code=4403)
        return

    await websocket.accept()
    current_user = await _websocket_user(websocket)
    if not current_user:
        await websocket.close(code=4401)
        return

    db = SessionLocal()
    try:
        freight = _freight_for_chat(db, freight_id)
        access = resolve_freight_chat_access(db, freight, current_user)
    except HTTPException:
        await websocket.close(code=4403)
        return
    finally:
        db.close()

    freight_chat_connections.add(freight_id, current_user.id, websocket)
    try:
        await websocket.send_json(
            {
                "type": "ready",
                "freight_id": freight_id,
                "is_writable": access.is_writable,
            }
        )
        while True:
            event = await websocket.receive_json()
            if isinstance(event, dict) and event.get("type") == "ping":
                await websocket.send_json({"type": "pong"})
    except (WebSocketDisconnect, ValueError, TypeError):
        pass
    finally:
        freight_chat_connections.remove(freight_id, websocket)
