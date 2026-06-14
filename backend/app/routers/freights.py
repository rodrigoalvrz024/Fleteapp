import secrets
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import (
    get_current_user,
    hash_password,
    require_role,
    verify_password,
)
from app.database import get_db
from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest, FreightStatus, TripStatusHistory
from app.models.user import User, UserRole
from app.schemas.freight import (
    DeliveryPinResponse,
    EvidenceViewResponse,
    FreightCreate,
    FreightResponse,
    FreightStatusUpdate,
)
from app.services.audit_service import record_audit_event
from app.services.freight_service import calculate_distance_km, can_transition, estimate_price
from app.services.storage_service import (
    create_freight_evidence_view_token,
    decode_freight_evidence_view_token,
    delete_private_document,
    stream_private_document,
    upload_freight_evidence,
)

router = APIRouter(prefix="/freights", tags=["Fletes"])
EVIDENCE_FIELDS = {
    "pickup": ("pickup_photo_ref", "pickup_photo_uploaded_at"),
    "delivery": ("delivery_photo_ref", "delivery_photo_uploaded_at"),
}

def _get_driver_for_user(db: Session, user: User) -> Driver | None:
    if user.role != UserRole.driver:
        return None
    return db.query(Driver).filter(Driver.user_id == user.id).first()

def _require_freight_view_access(
    freight: FreightRequest,
    db: Session,
    current_user: User,
) -> None:
    if current_user.role == UserRole.admin:
        return
    if current_user.role == UserRole.client and freight.client_id == current_user.id:
        return
    if current_user.role == UserRole.driver:
        driver = _get_driver_for_user(db, current_user)
        if driver and freight.driver_id == driver.id:
            return
        if (
            driver
            and driver.status == DriverStatus.approved
            and freight.status == FreightStatus.pending
            and freight.driver_id is None
        ):
            return
    raise HTTPException(status_code=403, detail="No tienes permiso para ver este flete")

def _require_freight_status_access(
    freight: FreightRequest,
    db: Session,
    current_user: User,
    new_status: FreightStatus,
) -> None:
    if current_user.role == UserRole.admin:
        return
    if (
        current_user.role == UserRole.client
        and freight.client_id == current_user.id
        and new_status == FreightStatus.cancelled
        and freight.status in (FreightStatus.pending, FreightStatus.accepted)
    ):
        return
    if current_user.role == UserRole.driver:
        driver = _get_driver_for_user(db, current_user)
        if driver and freight.driver_id == driver.id:
            return
    raise HTTPException(
        status_code=403,
        detail="Solo el conductor asignado o un admin puede actualizar el estado",
    )


def _require_assigned_driver(
    freight: FreightRequest,
    db: Session,
    current_user: User,
) -> Driver:
    driver = _get_driver_for_user(db, current_user)
    if not driver or freight.driver_id != driver.id:
        raise HTTPException(
            status_code=403,
            detail="Solo el conductor asignado puede realizar esta accion",
        )
    return driver

@router.post("", response_model=FreightResponse, status_code=201)
async def create_freight(
    data: FreightCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client"))
):
    dist   = calculate_distance_km(
        data.origin_lat, data.origin_lng,
        data.destination_lat, data.destination_lng
    )
    prices = estimate_price(
        distance_km  = dist,
        weight_kg    = data.cargo_weight_kg,
        helpers      = data.requires_helpers,
        is_urgent    = data.is_urgent,
        scheduled_at = data.scheduled_at,
    )

    freight = FreightRequest(
        client_id        = current_user.id,
        distance_km      = round(dist, 2),
        is_urgent        = data.is_urgent,
        mode             = prices["mode"],
        base_price       = prices["base_price"],
        client_pays      = prices["client_pays"],
        driver_receives  = prices["driver_receives"],
        platform_fee     = prices["platform_fee"],
        helpers_cost     = prices["helpers_cost"],
        estimated_price  = prices["client_pays"],  # compatibilidad
        origin_address      = data.origin_address,
        origin_lat          = data.origin_lat,
        origin_lng          = data.origin_lng,
        destination_address = data.destination_address,
        destination_lat     = data.destination_lat,
        destination_lng     = data.destination_lng,
        cargo_description   = data.cargo_description,
        cargo_weight_kg     = data.cargo_weight_kg,
        cargo_volume_m3     = data.cargo_volume_m3,
        requires_helpers    = data.requires_helpers,
        scheduled_at        = data.scheduled_at,
        last_modified_by    = current_user.id,
    )
    db.add(freight)
    db.flush()
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight",
        entity_id=freight.id,
        event_type="freight.created",
        after_data={
            "status": FreightStatus.pending.value,
            "distance_km": freight.distance_km,
            "client_pays": freight.client_pays,
            "driver_receives": freight.driver_receives,
            "platform_fee": freight.platform_fee,
            "mode": freight.mode,
        },
        request=request,
    )
    db.commit()
    db.refresh(freight)

    history = TripStatusHistory(
        freight_id = freight.id,
        status     = FreightStatus.pending,
        note       = f"Solicitud creada - Modo: {prices['mode']}"
    )
    db.add(history)
    db.commit()

    from app.services.notification_service import send_notification_to_drivers
    await send_notification_to_drivers(
        db    = db,
        title = "🚛 Nuevo flete disponible",
        body  = f"{'⚡ URGENTE' if data.is_urgent else '📅 Programado'} - ${prices['client_pays']:,.0f} CLP",
        data  = {"freight_id": str(freight.id), "type": "new_freight", "mode": prices["mode"]}
    )

    db.refresh(freight)
    return freight

@router.get("", response_model=List[FreightResponse])
def list_freights(status: str = None, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    query = db.query(FreightRequest)
    if current_user.role == UserRole.client:
        query = query.filter(FreightRequest.client_id == current_user.id)
    elif current_user.role == UserRole.driver:
        driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
        if status == "available":
            if driver and driver.status == DriverStatus.approved:
                query = query.filter(
                    FreightRequest.status == FreightStatus.pending,
                    FreightRequest.driver_id == None,
                )
            else:
                query = query.filter(False)
        else:
            query = query.filter(FreightRequest.driver_id == driver.id) if driver else query.filter(False)
    if status and status != "available":
        query = query.filter(FreightRequest.status == status)
    return query.order_by(FreightRequest.created_at.desc()).all()

@router.get("/{freight_id}", response_model=FreightResponse)
def get_freight(freight_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    _require_freight_view_access(freight, db, current_user)
    return freight


@router.post("/{freight_id}/delivery-pin", response_model=DeliveryPinResponse)
def generate_delivery_pin(
    freight_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client")),
):
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    if freight.client_id != current_user.id:
        raise HTTPException(status_code=403, detail="No tienes permiso para este flete")
    if freight.status not in (FreightStatus.accepted, FreightStatus.in_progress):
        raise HTTPException(
            status_code=400,
            detail="El PIN se puede generar cuando el flete fue aceptado",
        )

    pin = f"{secrets.randbelow(10000):04d}"
    generated_at = datetime.now(timezone.utc)
    freight.delivery_pin_hash = hash_password(pin)
    freight.delivery_pin_generated_at = generated_at
    freight.delivery_pin_verified_at = None
    freight.delivery_pin_failed_attempts = 0
    freight.last_modified_by = current_user.id
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight",
        entity_id=freight.id,
        event_type="freight.delivery_pin_generated",
        after_data={"generated_at": generated_at.isoformat()},
        request=request,
    )
    db.commit()
    return DeliveryPinResponse(pin=pin, generated_at=generated_at)


@router.post("/{freight_id}/evidence/{kind}", response_model=FreightResponse)
async def upload_evidence(
    freight_id: int,
    kind: str,
    request: Request,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    fields = EVIDENCE_FIELDS.get(kind)
    if not fields:
        raise HTTPException(status_code=400, detail="Tipo de evidencia invalido")
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    _require_assigned_driver(freight, db, current_user)

    expected_status = (
        FreightStatus.accepted if kind == "pickup" else FreightStatus.in_progress
    )
    if freight.status != expected_status:
        raise HTTPException(
            status_code=400,
            detail=(
                "La foto de retiro se carga antes de iniciar el viaje"
                if kind == "pickup"
                else "La foto de entrega se carga durante el viaje"
            ),
        )

    ref_field, uploaded_at_field = fields
    previous_ref = getattr(freight, ref_field)
    evidence_ref = await upload_freight_evidence(file, freight.id, kind)
    uploaded_at = datetime.now(timezone.utc)
    setattr(freight, ref_field, evidence_ref)
    setattr(freight, uploaded_at_field, uploaded_at)
    freight.last_modified_by = current_user.id
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight",
        entity_id=freight.id,
        event_type=f"freight.{kind}_photo_uploaded",
        after_data={"kind": kind, "uploaded_at": uploaded_at.isoformat()},
        request=request,
    )
    db.commit()
    db.refresh(freight)
    if previous_ref and previous_ref != evidence_ref:
        try:
            delete_private_document(previous_ref)
        except Exception:
            pass
    return freight


@router.get(
    "/{freight_id}/evidence/{kind}/view-url",
    response_model=EvidenceViewResponse,
)
def get_evidence_view_url(
    freight_id: int,
    kind: str,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    fields = EVIDENCE_FIELDS.get(kind)
    if not fields:
        raise HTTPException(status_code=400, detail="Tipo de evidencia invalido")
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    _require_freight_view_access(freight, db, current_user)
    evidence_ref = getattr(freight, fields[0])
    if not evidence_ref:
        raise HTTPException(status_code=404, detail="Evidencia no disponible")

    token, expires_at = create_freight_evidence_view_token(
        freight.id,
        kind,
        evidence_ref,
    )
    base_url = (
        settings.PUBLIC_API_URL.rstrip("/")
        if settings.PUBLIC_API_URL
        else str(request.base_url).rstrip("/")
    )
    return EvidenceViewResponse(
        url=f"{base_url}/freights/evidence/{token}",
        expires_at=expires_at,
    )


@router.get("/evidence/{token}", response_class=StreamingResponse)
def view_evidence(token: str, db: Session = Depends(get_db)):
    payload = decode_freight_evidence_view_token(token)
    freight = (
        db.query(FreightRequest)
        .filter(FreightRequest.id == payload.get("freight_id"))
        .first()
    )
    fields = EVIDENCE_FIELDS.get(payload.get("kind"))
    if not freight or not fields:
        raise HTTPException(status_code=404, detail="Evidencia no disponible")
    evidence_ref = getattr(freight, fields[0])
    if not evidence_ref or evidence_ref != payload.get("evidence_ref"):
        raise HTTPException(status_code=404, detail="Evidencia no disponible")
    return stream_private_document(evidence_ref)

@router.put("/{freight_id}/accept", response_model=FreightResponse)
def accept_freight(freight_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_role("driver"))):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver or driver.status != "approved":
        raise HTTPException(status_code=403, detail="Conductor no aprobado")

    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight or freight.status != FreightStatus.pending:
        raise HTTPException(status_code=400, detail="Flete no disponible")

    status_before = freight.status.value if hasattr(freight.status, "value") else str(freight.status)
    freight.driver_id = driver.id
    freight.status = FreightStatus.accepted
    freight.accepted_at = datetime.utcnow()
    freight.last_modified_by = current_user.id

    history = TripStatusHistory(freight_id=freight.id, status=FreightStatus.accepted, note=f"Aceptado por conductor {driver.id}")
    db.add(history)
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight",
        entity_id=freight.id,
        event_type="freight.accepted",
        before_data={"status": status_before, "driver_id": None},
        after_data={
            "status": FreightStatus.accepted.value,
            "driver_id": driver.id,
            "accepted_at": freight.accepted_at.isoformat(),
        },
        metadata={"driver_profile_id": driver.id},
    )
    db.commit()
    db.refresh(freight)
    return freight

@router.put("/{freight_id}/status", response_model=FreightResponse)
def update_status(
    freight_id: int,
    data: FreightStatusUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")

    _require_freight_status_access(freight, db, current_user, data.status)

    if not can_transition(freight.status, data.status):
        raise HTTPException(status_code=400, detail=f"No se puede pasar de {freight.status} a {data.status}")

    if data.status == FreightStatus.in_progress and not freight.pickup_photo_ref:
        raise HTTPException(
            status_code=400,
            detail="Debes subir una foto del retiro antes de iniciar el viaje",
        )
    if (
        data.status == FreightStatus.cancelled
        and current_user.role == UserRole.client
        and freight.pickup_photo_ref
    ):
        raise HTTPException(
            status_code=400,
            detail="El retiro ya fue registrado. Contacta a soporte para cancelar",
        )
    if data.status == FreightStatus.completed:
        if not freight.delivery_photo_ref:
            raise HTTPException(
                status_code=400,
                detail="Debes subir una foto de entrega antes de completar el viaje",
            )
        if not freight.delivery_pin_hash:
            raise HTTPException(
                status_code=400,
                detail="El cliente debe generar un PIN de entrega",
            )
        if freight.delivery_pin_failed_attempts >= 5:
            raise HTTPException(
                status_code=400,
                detail="PIN bloqueado. Solicita al cliente generar uno nuevo",
            )
        if not data.confirmation_pin or not verify_password(
            data.confirmation_pin,
            freight.delivery_pin_hash,
        ):
            freight.delivery_pin_failed_attempts += 1
            db.commit()
            raise HTTPException(status_code=400, detail="PIN de entrega incorrecto")

    status_before = freight.status.value if hasattr(freight.status, "value") else str(freight.status)
    freight.status = data.status
    if data.status == FreightStatus.in_progress:
        freight.started_at = datetime.utcnow()
    elif data.status == FreightStatus.completed:
        freight.completed_at = datetime.utcnow()
        freight.final_price = freight.estimated_price
        freight.delivery_pin_verified_at = datetime.now(timezone.utc)
    elif data.status == FreightStatus.cancelled:
        freight.cancelled_at = datetime.utcnow()
        freight.cancel_reason = data.note
    freight.last_modified_by = current_user.id

    history = TripStatusHistory(freight_id=freight.id, status=data.status, note=data.note)
    db.add(history)
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight",
        entity_id=freight.id,
        event_type="freight.status_changed",
        before_data={"status": status_before},
        after_data={
            "status": data.status.value,
            "final_price": freight.final_price,
            "cancel_reason": freight.cancel_reason,
        },
        reason=data.note,
        request=request,
    )
    db.commit()
    db.refresh(freight)
    return freight

from app.services.maps_service import get_distance_and_duration
from app.services.freight_service import estimate_price

@router.post("/estimate")
async def estimate_freight(
    origin_lat:       float,
    origin_lng:       float,
    destination_lat:  float,
    destination_lng:  float,
    cargo_weight_kg:  float,
    requires_helpers: int = 0,
    is_urgent:        bool = False,
    scheduled_at:     Optional[datetime] = None,
    current_user = Depends(get_current_user)
):
    from app.services.maps_service import get_distance_and_duration
    from datetime import datetime as dt

    map_data = await get_distance_and_duration(
        origin_lat, origin_lng, destination_lat, destination_lng
    )
    prices = estimate_price(
        distance_km  = map_data["distance_km"],
        weight_kg    = cargo_weight_kg,
        helpers      = requires_helpers,
        is_urgent    = is_urgent,
        scheduled_at = scheduled_at or dt.utcnow(),
    )

    return {
        "distance_km":      round(map_data["distance_km"], 2),
        "duration_minutes": map_data["duration_minutes"],
        "distance_text":    map_data.get("distance_text"),
        "duration_text":    map_data.get("duration_text"),
        "mode":             prices["mode"],
        "base_price":       prices["base_price"],
        "client_pays":      prices["client_pays"],
        "driver_receives":  prices["driver_receives"],
        "platform_fee":     prices["platform_fee"],
        "helpers_cost":     prices["helpers_cost"],
        "minimum_applied":  prices["minimum_applied"],
    }
