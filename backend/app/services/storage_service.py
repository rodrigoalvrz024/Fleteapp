import io
import mimetypes
from datetime import datetime, timedelta, timezone
from pathlib import PurePosixPath
from uuid import uuid4

from fastapi import HTTPException, UploadFile, status
from fastapi.responses import StreamingResponse
from google.cloud import storage
from jose import JWTError, jwt

from app.core.config import settings


ALLOWED_UPLOAD_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "application/pdf": ".pdf",
}
DOCUMENT_VIEW_PURPOSE = "driver_document_view"


def _max_upload_bytes() -> int:
    return settings.DRIVER_DOCUMENT_MAX_MB * 1024 * 1024


def _ensure_storage_configured() -> None:
    if not settings.DRIVER_DOCUMENTS_BUCKET:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Almacenamiento privado de documentos no configurado",
        )


def _bucket():
    _ensure_storage_configured()
    return storage.Client().bucket(settings.DRIVER_DOCUMENTS_BUCKET)


def _object_name(driver_id: int, field: str, extension: str) -> str:
    return f"drivers/{driver_id}/{field}/{uuid4().hex}{extension}"


async def upload_driver_document(file: UploadFile, driver_id: int, field: str) -> str:
    content_type = file.content_type or "application/octet-stream"
    extension = ALLOWED_UPLOAD_TYPES.get(content_type)
    if not extension:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Formato no permitido. Usa JPG, PNG, WEBP o PDF.",
        )

    content = await file.read()
    if len(content) > _max_upload_bytes():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El archivo supera el maximo de {settings.DRIVER_DOCUMENT_MAX_MB} MB.",
        )

    object_name = _object_name(driver_id, field, extension)
    blob = _bucket().blob(object_name)
    blob.upload_from_file(
        io.BytesIO(content),
        content_type=content_type,
        rewind=True,
    )
    return object_name


def create_driver_document_view_token(
    driver_id: int,
    document_type: str,
    document_ref: str,
) -> tuple[str, datetime]:
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.DRIVER_DOCUMENT_VIEW_EXPIRE_MINUTES
    )
    payload = {
        "purpose": DOCUMENT_VIEW_PURPOSE,
        "driver_id": driver_id,
        "document_type": document_type,
        "document_ref": document_ref,
        "exp": expires_at,
    }
    token = jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return token, expires_at


def decode_driver_document_view_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Documento no disponible",
        )
    if payload.get("purpose") != DOCUMENT_VIEW_PURPOSE:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Documento no disponible",
        )
    return payload


def is_external_document_ref(document_ref: str) -> bool:
    return document_ref.startswith("http://") or document_ref.startswith("https://")


def stream_private_document(document_ref: str) -> StreamingResponse:
    _ensure_storage_configured()
    object_name = _normalize_document_ref(document_ref)
    blob = _bucket().blob(object_name)
    if not blob.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Documento no encontrado",
        )

    content = blob.download_as_bytes()
    content_type = blob.content_type or mimetypes.guess_type(object_name)[0]
    filename = PurePosixPath(object_name).name
    return StreamingResponse(
        io.BytesIO(content),
        media_type=content_type or "application/octet-stream",
        headers={
            "Cache-Control": "private, no-store",
            "Content-Disposition": f'inline; filename="{filename}"',
        },
    )


def _normalize_document_ref(document_ref: str) -> str:
    if document_ref.startswith("gs://"):
        prefix = f"gs://{settings.DRIVER_DOCUMENTS_BUCKET}/"
        if not document_ref.startswith(prefix):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Documento no disponible",
            )
        return document_ref[len(prefix) :]
    return document_ref
