import io
import hashlib
import mimetypes
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import PurePosixPath
from urllib.parse import quote
from uuid import uuid4

import httpx
from fastapi import HTTPException, UploadFile, status
from fastapi.responses import StreamingResponse
from jose import JWTError, jwt

from app.core.config import settings


ALLOWED_UPLOAD_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/heic": ".heic",
    "image/heif": ".heif",
    "image/heic-sequence": ".heic",
    "image/heif-sequence": ".heif",
    "application/pdf": ".pdf",
}
ALLOWED_IMAGE_UPLOAD_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
    "image/heic-sequence",
    "image/heif-sequence",
}
HEIF_BRANDS = {
    b"heic",
    b"heix",
    b"hevc",
    b"hevx",
    b"heim",
    b"heis",
    b"hevm",
    b"hevs",
    b"mif1",
    b"msf1",
}
DOCUMENT_VIEW_PURPOSE = "driver_document_view"
FREIGHT_EVIDENCE_VIEW_PURPOSE = "freight_evidence_view"
CHAT_IMAGE_VIEW_PURPOSE = "freight_chat_image_view"
FILE_SIGNATURES = {
    "image/jpeg": (b"\xff\xd8\xff",),
    "image/png": (b"\x89PNG\r\n\x1a\n",),
    "image/webp": (b"RIFF",),
    "application/pdf": (b"%PDF-",),
}
PNG_METADATA_CHUNKS = {b"eXIf", b"iTXt", b"tEXt", b"tIME", b"zTXt"}
WEBP_METADATA_CHUNKS = {b"EXIF", b"ICCP", b"XMP "}


def _max_upload_bytes() -> int:
    return settings.DRIVER_DOCUMENT_MAX_MB * 1024 * 1024


def _max_freight_evidence_bytes() -> int:
    return settings.FREIGHT_EVIDENCE_MAX_MB * 1024 * 1024


def _max_chat_image_bytes() -> int:
    return settings.CHAT_IMAGE_MAX_MB * 1024 * 1024


@dataclass(frozen=True)
class PrivateImageUpload:
    reference: str
    content_type: str
    size_bytes: int


async def _read_limited_upload(file: UploadFile, max_bytes: int, message: str) -> bytes:
    # UploadFile may be backed by a temporary file. Read at most one extra byte
    # so a malicious upload cannot occupy the application's memory.
    content = await file.read(max_bytes + 1)
    if len(content) > max_bytes:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=message)
    return content


def _ensure_storage_configured() -> None:
    if not (
        settings.DRIVER_DOCUMENTS_BUCKET
        and settings.SUPABASE_URL
        and settings.SUPABASE_SERVICE_ROLE_KEY
    ):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Almacenamiento privado de Supabase no configurado",
        )


def _validate_file_signature(content_type: str, content: bytes) -> None:
    if content_type in {
        "image/heic",
        "image/heif",
        "image/heic-sequence",
        "image/heif-sequence",
    }:
        if not _is_heif_content(content):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El contenido del archivo no coincide con el formato declarado.",
            )
        return

    signatures = FILE_SIGNATURES.get(content_type, ())
    if not signatures or not any(content.startswith(signature) for signature in signatures):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El contenido del archivo no coincide con el formato declarado.",
        )
    if content_type == "image/webp" and content[8:12] != b"WEBP":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El contenido del archivo no coincide con el formato declarado.",
        )


def _is_heif_content(content: bytes) -> bool:
    if len(content) < 12 or content[4:8] != b"ftyp":
        return False
    brands = [content[8:12]]
    brands.extend(content[i : i + 4] for i in range(16, len(content) - 3, 4))
    return any(brand in HEIF_BRANDS for brand in brands)


def _detect_upload_type(content: bytes, declared_type: str, filename: str) -> str:
    if content.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if (
        content.startswith(b"RIFF")
        and len(content) >= 12
        and content[8:12] == b"WEBP"
    ):
        return "image/webp"
    if content.startswith(b"%PDF-"):
        return "application/pdf"
    if _is_heif_content(content):
        lower = filename.lower()
        if lower.endswith(".heic"):
            return "image/heic"
        if lower.endswith(".heif"):
            return "image/heif"
        if declared_type in ALLOWED_UPLOAD_TYPES:
            return declared_type
        return "image/heic"
    return declared_type


def _strip_image_metadata(content_type: str, content: bytes) -> bytes:
    if content_type == "image/jpeg":
        return _strip_jpeg_metadata(content)
    if content_type == "image/png":
        return _strip_png_metadata(content)
    if content_type == "image/webp":
        return _strip_webp_metadata(content)
    return content


def _strip_jpeg_metadata(content: bytes) -> bytes:
    if not content.startswith(b"\xff\xd8"):
        return content

    output = bytearray(content[:2])
    index = 2
    length = len(content)
    while index < length:
        if content[index] != 0xFF:
            return content
        while index < length and content[index] == 0xFF:
            index += 1
        if index >= length:
            return content

        marker = content[index]
        index += 1
        if marker == 0xDA:  # Start of scan: image payload follows.
            output.extend((0xFF, marker))
            output.extend(content[index:])
            return bytes(output)
        if marker == 0xD9:
            output.extend((0xFF, marker))
            return bytes(output)
        if marker == 0x01 or 0xD0 <= marker <= 0xD7:
            output.extend((0xFF, marker))
            continue
        if index + 2 > length:
            return content

        segment_length = int.from_bytes(content[index : index + 2], "big")
        if segment_length < 2 or index + segment_length > length:
            return content

        segment = content[index : index + segment_length]
        is_metadata_segment = 0xE0 <= marker <= 0xEF or marker == 0xFE
        if not is_metadata_segment:
            output.extend((0xFF, marker))
            output.extend(segment)
        index += segment_length

    return bytes(output)


def _strip_png_metadata(content: bytes) -> bytes:
    signature = b"\x89PNG\r\n\x1a\n"
    if not content.startswith(signature):
        return content

    output = bytearray(signature)
    index = len(signature)
    length = len(content)
    while index + 12 <= length:
        chunk_length = int.from_bytes(content[index : index + 4], "big")
        chunk_type = content[index + 4 : index + 8]
        chunk_end = index + 12 + chunk_length
        if chunk_end > length:
            return content
        if chunk_type not in PNG_METADATA_CHUNKS:
            output.extend(content[index:chunk_end])
        index = chunk_end
        if chunk_type == b"IEND":
            return bytes(output)
    return content


def _strip_webp_metadata(content: bytes) -> bytes:
    if not (
        content.startswith(b"RIFF")
        and len(content) >= 12
        and content[8:12] == b"WEBP"
    ):
        return content

    output = bytearray(b"RIFF\x00\x00\x00\x00WEBP")
    index = 12
    length = len(content)
    while index + 8 <= length:
        chunk_type = content[index : index + 4]
        chunk_size = int.from_bytes(content[index + 4 : index + 8], "little")
        chunk_end = index + 8 + chunk_size
        padded_end = chunk_end + (chunk_size % 2)
        if padded_end > length:
            return content
        if chunk_type not in WEBP_METADATA_CHUNKS:
            output.extend(content[index:padded_end])
        index = padded_end

    riff_size = len(output) - 8
    output[4:8] = riff_size.to_bytes(4, "little")
    return bytes(output)


def _supabase_object_url(object_name: str) -> str:
    _ensure_storage_configured()
    bucket = quote(settings.DRIVER_DOCUMENTS_BUCKET, safe="")
    object_path = quote(object_name, safe="/")
    return f"{settings.SUPABASE_URL.rstrip('/')}/storage/v1/object/{bucket}/{object_path}"


def _supabase_headers(content_type: str | None = None) -> dict[str, str]:
    key = settings.SUPABASE_SERVICE_ROLE_KEY
    headers = {"apikey": key}
    # Modern sb_secret keys are API keys, not JWT bearer tokens. Legacy
    # service_role keys still use Authorization to bypass Storage RLS.
    if not key.startswith("sb_secret_"):
        headers["Authorization"] = f"Bearer {key}"
    if content_type:
        headers["Content-Type"] = content_type
    return headers


def _upload_private_object(object_name: str, content: bytes, content_type: str) -> None:
    try:
        response = httpx.post(
            _supabase_object_url(object_name),
            headers={**_supabase_headers(content_type), "x-upsert": "false"},
            content=content,
            timeout=20.0,
        )
    except httpx.RequestError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No fue posible guardar el archivo. Intenta nuevamente.",
        )
    if response.status_code in {200, 201}:
        return
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="No fue posible guardar el archivo. Intenta nuevamente.",
    )


def _object_name(driver_id: int, field: str, extension: str) -> str:
    return f"drivers/{driver_id}/{field}/{uuid4().hex}{extension}"


async def upload_driver_document(file: UploadFile, driver_id: int, field: str) -> str:
    declared_type = file.content_type or "application/octet-stream"
    max_bytes = _max_upload_bytes()
    content = await _read_limited_upload(
        file,
        max_bytes,
        f"El archivo supera el maximo de {settings.DRIVER_DOCUMENT_MAX_MB} MB.",
    )
    content_type = _detect_upload_type(content, declared_type, file.filename or "")
    extension = ALLOWED_UPLOAD_TYPES.get(content_type)
    if not extension:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Formato no permitido. Usa JPG, PNG, WEBP, HEIC, HEIF o PDF.",
        )

    _validate_file_signature(content_type, content)
    content = _strip_image_metadata(content_type, content)
    _validate_file_signature(content_type, content)

    object_name = _object_name(driver_id, field, extension)
    _upload_private_object(object_name, content, content_type)
    return object_name


async def upload_freight_evidence(file: UploadFile, freight_id: int, kind: str) -> str:
    declared_type = file.content_type or "application/octet-stream"
    max_bytes = _max_freight_evidence_bytes()
    content = await _read_limited_upload(
        file,
        max_bytes,
        f"La foto supera el maximo de {settings.FREIGHT_EVIDENCE_MAX_MB} MB.",
    )
    content_type = _detect_upload_type(content, declared_type, file.filename or "")
    extension = ALLOWED_UPLOAD_TYPES.get(content_type)
    if not extension or content_type not in ALLOWED_IMAGE_UPLOAD_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Formato no permitido. Usa JPG, PNG, WEBP, HEIC o HEIF.",
        )

    _validate_file_signature(content_type, content)
    content = _strip_image_metadata(content_type, content)
    _validate_file_signature(content_type, content)

    object_name = (
        f"freights/{freight_id}/evidence/{kind}/{uuid4().hex}{extension}"
    )
    _upload_private_object(object_name, content, content_type)
    return object_name


async def upload_freight_chat_image(
    file: UploadFile,
    freight_id: int,
) -> PrivateImageUpload:
    declared_type = file.content_type or "application/octet-stream"
    content = await _read_limited_upload(
        file,
        _max_chat_image_bytes(),
        f"La foto supera el maximo de {settings.CHAT_IMAGE_MAX_MB} MB.",
    )
    content_type = _detect_upload_type(content, declared_type, file.filename or "")
    extension = ALLOWED_UPLOAD_TYPES.get(content_type)
    if not extension or content_type not in ALLOWED_IMAGE_UPLOAD_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Formato no permitido. Usa JPG, PNG, WEBP, HEIC o HEIF.",
        )

    _validate_file_signature(content_type, content)
    content = _strip_image_metadata(content_type, content)
    _validate_file_signature(content_type, content)

    object_name = f"freights/{freight_id}/chat/{uuid4().hex}{extension}"
    _upload_private_object(object_name, content, content_type)
    return PrivateImageUpload(
        reference=object_name,
        content_type=content_type,
        size_bytes=len(content),
    )


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
    token = jwt.encode(
        payload,
        _view_token_key(DOCUMENT_VIEW_PURPOSE),
        algorithm=settings.ALGORITHM,
    )
    return token, expires_at


def decode_driver_document_view_token(token: str) -> dict:
    try:
        payload = jwt.decode(
            token,
            _view_token_key(DOCUMENT_VIEW_PURPOSE),
            algorithms=[settings.ALGORITHM],
        )
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


def create_freight_evidence_view_token(
    freight_id: int,
    kind: str,
    evidence_ref: str,
) -> tuple[str, datetime]:
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.FREIGHT_EVIDENCE_VIEW_EXPIRE_MINUTES
    )
    payload = {
        "purpose": FREIGHT_EVIDENCE_VIEW_PURPOSE,
        "freight_id": freight_id,
        "kind": kind,
        "evidence_ref": evidence_ref,
        "exp": expires_at,
    }
    token = jwt.encode(
        payload,
        _view_token_key(FREIGHT_EVIDENCE_VIEW_PURPOSE),
        algorithm=settings.ALGORITHM,
    )
    return token, expires_at


def decode_freight_evidence_view_token(token: str) -> dict:
    try:
        payload = jwt.decode(
            token,
            _view_token_key(FREIGHT_EVIDENCE_VIEW_PURPOSE),
            algorithms=[settings.ALGORITHM],
        )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Evidencia no disponible",
        )
    if payload.get("purpose") != FREIGHT_EVIDENCE_VIEW_PURPOSE:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Evidencia no disponible",
        )
    return payload


def create_chat_image_view_token(
    freight_id: int,
    message_id: int,
    attachment_ref: str,
) -> tuple[str, datetime]:
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.CHAT_IMAGE_VIEW_EXPIRE_MINUTES
    )
    payload = {
        "purpose": CHAT_IMAGE_VIEW_PURPOSE,
        "freight_id": freight_id,
        "message_id": message_id,
        "attachment_ref": attachment_ref,
        "exp": expires_at,
    }
    token = jwt.encode(
        payload,
        _view_token_key(CHAT_IMAGE_VIEW_PURPOSE),
        algorithm=settings.ALGORITHM,
    )
    return token, expires_at


def decode_chat_image_view_token(token: str) -> dict:
    try:
        payload = jwt.decode(
            token,
            _view_token_key(CHAT_IMAGE_VIEW_PURPOSE),
            algorithms=[settings.ALGORITHM],
        )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Imagen no disponible",
        )
    if payload.get("purpose") != CHAT_IMAGE_VIEW_PURPOSE:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Imagen no disponible",
        )
    return payload


def is_external_document_ref(document_ref: str) -> bool:
    return document_ref.startswith("http://") or document_ref.startswith("https://")


def delete_private_document(document_ref: str | None) -> dict:
    if not document_ref:
        return {"deleted": False, "reason": "empty"}
    if is_external_document_ref(document_ref):
        return {"deleted": False, "reason": "external"}

    object_name = _normalize_document_ref(document_ref)
    try:
        response = httpx.delete(
            _supabase_object_url(object_name),
            headers=_supabase_headers(),
            timeout=20.0,
        )
    except httpx.RequestError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No fue posible eliminar el archivo. Intenta nuevamente.",
        )
    if response.status_code == status.HTTP_404_NOT_FOUND:
        return {"deleted": False, "reason": "not_found", "object": object_name}
    if response.status_code not in {status.HTTP_200_OK, status.HTTP_204_NO_CONTENT}:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No fue posible eliminar el archivo. Intenta nuevamente.",
        )
    return {"deleted": True, "object": object_name}


def stream_private_document(document_ref: str) -> StreamingResponse:
    _ensure_storage_configured()
    if is_external_document_ref(document_ref) and not settings.ALLOW_EXTERNAL_DOCUMENT_REFS:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Documento no disponible",
        )
    object_name = _normalize_document_ref(document_ref)
    try:
        response = httpx.get(
            _supabase_object_url(object_name),
            headers=_supabase_headers(),
            timeout=20.0,
        )
    except httpx.RequestError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Documento no disponible",
        )
    if response.status_code == status.HTTP_404_NOT_FOUND:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Documento no encontrado",
        )
    if response.status_code != status.HTTP_200_OK:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Documento no disponible",
        )

    content_type = response.headers.get("content-type") or mimetypes.guess_type(object_name)[0]
    filename = PurePosixPath(object_name).name
    content_disposition = "attachment" if content_type == "application/pdf" else "inline"
    return StreamingResponse(
        io.BytesIO(response.content),
        media_type=content_type or "application/octet-stream",
        headers={
            "Cache-Control": "private, no-store",
            "Content-Disposition": f'{content_disposition}; filename="{filename}"',
            "Content-Security-Policy": "sandbox",
            "Content-Length": str(len(response.content)),
        },
    )


def _view_token_key(purpose: str) -> str:
    material = f"{settings.SECRET_KEY}:{purpose}:v1".encode("utf-8")
    return hashlib.sha256(material).hexdigest()


def _normalize_document_ref(document_ref: str) -> str:
    if is_external_document_ref(document_ref):
        if settings.ALLOW_EXTERNAL_DOCUMENT_REFS:
            return document_ref
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Documento no disponible",
        )
    if document_ref.startswith("gs://"):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Documento no disponible",
        )
    normalized = str(PurePosixPath(document_ref))
    if normalized.startswith("../") or normalized == ".." or "/../" in normalized:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Documento no disponible",
        )
    return normalized
