import secrets
from datetime import datetime, timedelta, timezone
from typing import List, Literal, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session, joinedload, selectinload

from app.core.config import settings
from app.core.rate_limit import check_rate_limit
from app.core.security import (
    get_current_user,
    hash_password,
    require_role,
    verify_password,
)
from app.database import get_db
from app.models.driver import Driver, DriverStatus
from app.models.freight_driver_decline import FreightDriverDecline
from app.models.freight import FreightCargoPhoto, FreightRequest, FreightStatus, TripStatusHistory
from app.models.payment import Payment, PaymentStatus
from app.models.pricing_quote import FreightPriceQuote
from app.models.user import User, UserRole
from app.schemas.freight import (
    DeliveryPinResponse,
    DriverLiveLocationResponse,
    DriverLocationUpdate,
    EvidenceViewResponse,
    FreightDeclineResponse,
    FreightCreate,
    FreightCreateResponse,
    FreightAcceptRequest,
    FreightResponse,
    FreightStatusUpdate,
)
from app.services.audit_service import record_audit_event
from app.services.driver_operational_service import require_driver_can_operate
from app.services.freight_matching_service import compatible_vehicles, driver_matches_freight
from app.services.freight_service import (
    PRICING_VERSION,
    can_transition,
    normalize_service_type,
)
from app.services.chat_connections import freight_chat_connections
from app.services.chat_service import CHAT_WRITABLE_STATUSES
from app.services.maps_service import RouteCalculationError
from app.services.pricing_estimate_service import calculate_pricing_estimate
from app.services.pricing_history_service import record_pricing_snapshot
from app.services.pricing_quote_service import consume_pricing_quote
from app.services.pricing_service import PricingInputError
from app.services.payout_service import ensure_driver_payout
from app.services.storage_service import (
    create_freight_evidence_view_token,
    create_cargo_photo_view_token,
    decode_cargo_photo_view_token,
    decode_freight_evidence_view_token,
    delete_private_document,
    stream_private_document,
    is_valid_staged_freight_cargo_ref,
    upload_staged_freight_cargo_photo,
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
            and freight.status == FreightStatus.pending
            and freight.driver_id is None
        ):
            require_driver_can_operate(driver)
            if (
                not freight.payment
                or freight.payment.status != PaymentStatus.authorized
            ):
                raise HTTPException(status_code=404, detail="Flete no disponible")
            was_declined = (
                db.query(FreightDriverDecline.id)
                .filter(
                    FreightDriverDecline.freight_id == freight.id,
                    FreightDriverDecline.driver_id == driver.id,
                )
                .first()
            )
            if was_declined:
                raise HTTPException(status_code=403, detail="Ya rechazaste este flete")
            if not driver_matches_freight(driver, freight):
                raise HTTPException(status_code=403, detail="Tu vehiculo no es compatible con este flete")
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


def _as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _live_location_window(
    freight: FreightRequest,
    now: datetime,
) -> tuple[bool, datetime | None]:
    """Return whether a freight may expose a driver's active-trip location."""
    if not freight.driver_id or freight.status not in (
        FreightStatus.accepted,
        FreightStatus.in_progress,
    ):
        return False, None

    scheduled_at = _as_utc(freight.scheduled_at)
    if scheduled_at and not freight.is_urgent:
        available_from = scheduled_at - timedelta(
            minutes=settings.DRIVER_LOCATION_EARLY_ACCESS_MINUTES
        )
        if now < available_from:
            return False, available_from
    return True, None


def _live_location_response(
    freight: FreightRequest,
    now: datetime,
) -> DriverLiveLocationResponse:
    window_open, available_from = _live_location_window(freight, now)
    updated_at = _as_utc(freight.driver_location_updated_at)
    has_position = (
        freight.driver_location_lat is not None
        and freight.driver_location_lng is not None
    )
    is_stale = bool(
        updated_at
        and (now - updated_at).total_seconds() > settings.DRIVER_LOCATION_STALE_SECONDS
    )
    visible = window_open and has_position
    return DriverLiveLocationResponse(
        freight_id=freight.id,
        visible=visible,
        latitude=freight.driver_location_lat if visible else None,
        longitude=freight.driver_location_lng if visible else None,
        accuracy_m=freight.driver_location_accuracy_m if visible else None,
        heading=freight.driver_location_heading if visible else None,
        updated_at=updated_at if visible else None,
        is_stale=is_stale if visible else False,
        available_from=available_from,
    )


def _clear_live_location(freight: FreightRequest) -> None:
    freight.driver_location_lat = None
    freight.driver_location_lng = None
    freight.driver_location_accuracy_m = None
    freight.driver_location_heading = None
    freight.driver_location_updated_at = None


def _require_cargo_photo_view_access(
    freight: FreightRequest,
    current_user: User,
) -> None:
    if current_user.role == UserRole.admin:
        return
    if current_user.role == UserRole.client and freight.client_id == current_user.id:
        return
    if (
        current_user.role == UserRole.driver
        and freight.driver
        and freight.driver.user_id == current_user.id
    ):
        return
    raise HTTPException(status_code=403, detail="No tienes permiso para ver las fotos de la carga")

@router.post("", response_model=FreightCreateResponse, status_code=201)
async def create_freight(
    data: FreightCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client"))
):
    check_rate_limit(
        request,
        scope="freight-create",
        identifier=str(current_user.id),
        max_attempts=30,
        window_seconds=60 * 60,
    )
    confirmed_at = datetime.now(timezone.utc)
    quote: FreightPriceQuote | None = None
    if data.quote_id:
        quote = consume_pricing_quote(
            db,
            quote_id=data.quote_id,
            client_id=current_user.id,
            data=data,
            now=confirmed_at,
        )
        map_data = {
            "distance_km": quote.route_distance_km,
            "duration_minutes": quote.route_duration_minutes,
            "provider": quote.route_provider,
            "calculated_at": quote.route_calculated_at,
        }
        prices = quote.pricing_components
    else:
        try:
            map_data, prices = await calculate_pricing_estimate(
                data,
                request_id=getattr(request.state, "request_id", None),
            )
        except RouteCalculationError:
            raise HTTPException(
                status_code=503,
                detail="No pudimos calcular la tarifa en este momento. Intenta nuevamente.",
            )
        except PricingInputError as exc:
            raise HTTPException(status_code=422, detail=str(exc))

    if prices.get("requires_manual_quote"):
        raise HTTPException(
            status_code=409,
            detail={
                "code": "manual_quote_required",
                "message": "Esta carga necesita una cotizacion personalizada.",
                "requires_manual_quote": True,
            },
        )

    freight = FreightRequest(
        client_id        = current_user.id,
        distance_km      = round(map_data["distance_km"], 2),
        estimated_duration_minutes = map_data.get("duration_minutes"),
        service_type     = normalize_service_type(data.service_type),
        recommended_vehicle_type = prices["recommended_vehicle_type"],
        selected_vehicle_type = prices["selected_vehicle_type"],
        pricing_version = prices["pricing_version"],
        pricing_type = prices["pricing_type"],
        requires_manual_quote = False,
        route_provider = map_data.get("provider"),
        route_calculated_at = map_data.get("calculated_at"),
        quote_expires_at = quote.expires_at if quote else None,
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
        extra_stops         = data.extra_stops,
        pickup_floor        = data.pickup_floor,
        delivery_floor      = data.delivery_floor,
        pickup_has_elevator = data.pickup_has_elevator,
        delivery_has_elevator = data.delivery_has_elevator,
        scheduled_at        = data.scheduled_at,
        requested_at        = confirmed_at,
        price_estimated_at  = confirmed_at,
        customer_confirmed_at = confirmed_at,
        last_modified_by    = current_user.id,
    )
    db.add(freight)
    db.flush()
    for photo_ref in dict.fromkeys(data.cargo_photo_refs):
        try:
            valid_ref = is_valid_staged_freight_cargo_ref(photo_ref, current_user.id)
        except HTTPException:
            valid_ref = False
        if not valid_ref:
            raise HTTPException(status_code=422, detail="Una foto de la carga no es valida")
        db.add(
            FreightCargoPhoto(
                freight_id=freight.id,
                client_id=current_user.id,
                object_ref=photo_ref,
                content_type="image/*",
                size_bytes=0,
            )
        )
    if quote:
        quote.used_at = confirmed_at
        quote.freight_id = freight.id
    snapshot_components = {
        **prices,
        "route_provider": freight.route_provider,
        "route_calculated_at": (
            freight.route_calculated_at.isoformat()
            if freight.route_calculated_at
            else None
        ),
        "quote_id": quote.id if quote else None,
    }
    record_pricing_snapshot(
        db,
        freight,
        snapshot_type="customer_confirmed",
        pricing_components=snapshot_components,
    )
    history = TripStatusHistory(
        freight_id=freight.id,
        status=FreightStatus.pending,
        note=f"Solicitud creada - Modo: {prices['mode']}",
    )
    db.add(history)
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
            "pricing_version": freight.pricing_version,
            "route_provider": freight.route_provider,
            "cargo_photo_count": len(data.cargo_photo_refs),
        },
        request=request,
    )
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight",
        entity_id=freight.id,
        event_type="pricing_estimated",
        after_data={
            "pricing_version": prices["pricing_version"],
            "estimated_customer_price": freight.estimated_price,
            "estimated_distance_km": freight.distance_km,
            "estimated_duration_minutes": freight.estimated_duration_minutes,
            "recommended_vehicle_type": freight.recommended_vehicle_type,
            "route_provider": freight.route_provider,
        },
        request=request,
    )
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight",
        entity_id=freight.id,
        event_type="pricing_confirmed",
        after_data={
            "accepted_customer_price": freight.client_pays,
            "pricing_type": "automatic",
        },
        request=request,
    )
    db.commit()
    db.refresh(freight)

    # The freight is intentionally private until the client confirms Webpay.
    # Payment authorization publishes it and triggers the driver notification.
    return freight


@router.post("/cargo-photos", status_code=201)
async def upload_cargo_photo(
    request: Request,
    file: UploadFile = File(...),
    current_user: User = Depends(require_role("client")),
):
    """Stage an image before a client confirms a freight."""
    check_rate_limit(
        request,
        scope="freight-cargo-photo-upload",
        identifier=str(current_user.id),
        max_attempts=20,
        window_seconds=60 * 60,
    )
    uploaded = await upload_staged_freight_cargo_photo(file, current_user.id)
    return {
        "reference": uploaded.reference,
        "content_type": uploaded.content_type,
        "size_bytes": uploaded.size_bytes,
    }

@router.get("", response_model=List[FreightResponse])
def list_freights(
    status: FreightStatus | Literal["available"] | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(FreightRequest).options(
        selectinload(FreightRequest.status_history),
        selectinload(FreightRequest.payment),
        selectinload(FreightRequest.rating),
        selectinload(FreightRequest.cargo_photos),
        selectinload(FreightRequest.feedback_entries),
        joinedload(FreightRequest.driver).joinedload(Driver.user),
        joinedload(FreightRequest.driver).selectinload(Driver.vehicles),
        joinedload(FreightRequest.actual_vehicle),
    )
    if current_user.role == UserRole.client:
        query = query.filter(FreightRequest.client_id == current_user.id)
    elif current_user.role == UserRole.driver:
        driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
        if status == "available":
            if not driver:
                query = query.filter(False)
            else:
                try:
                    require_driver_can_operate(driver)
                except HTTPException:
                    query = query.filter(False)
                    return query.order_by(FreightRequest.created_at.desc()).all()
                query = query.join(Payment, Payment.freight_id == FreightRequest.id).filter(
                    Payment.status == PaymentStatus.authorized,
                    FreightRequest.status == FreightStatus.pending,
                    FreightRequest.driver_id == None,
                    ~db.query(FreightDriverDecline.id)
                    .filter(
                        FreightDriverDecline.freight_id == FreightRequest.id,
                        FreightDriverDecline.driver_id == driver.id,
                    )
                    .exists(),
                )
        else:
            query = query.filter(FreightRequest.driver_id == driver.id) if driver else query.filter(False)
    if status and status != "available":
        query = query.filter(FreightRequest.status == status)
    freights = query.order_by(FreightRequest.created_at.desc()).all()
    if current_user.role == UserRole.driver and status == "available" and driver:
        return [freight for freight in freights if driver_matches_freight(driver, freight)]
    return freights

@router.get("/{freight_id}", response_model=FreightResponse)
def get_freight(
    freight_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    _require_freight_view_access(freight, db, current_user)
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight",
        entity_id=freight.id,
        event_type="app.freight_detail_view",
        request=request,
        metadata={
            "viewer_role": current_user.role.value
            if hasattr(current_user.role, "value")
            else str(current_user.role),
            "status": freight.status.value
            if hasattr(freight.status, "value")
            else str(freight.status),
            "client_id": freight.client_id,
            "driver_id": freight.driver_id,
            "distance_km": freight.distance_km,
            "is_urgent": freight.is_urgent,
            "requires_helpers": freight.requires_helpers,
            "estimated_price": freight.estimated_price,
        },
    )
    if current_user.role == UserRole.client and freight.driver_id:
        record_audit_event(
            db,
            actor=current_user,
            entity_type="driver",
            entity_id=freight.driver_id,
            event_type="app.driver_profile_view",
            request=request,
            metadata={
                "source": "freight_detail_driver_summary",
                "freight_id": freight.id,
                "status": freight.status.value
                if hasattr(freight.status, "value")
                else str(freight.status),
            },
        )
    db.commit()
    return freight


def _require_live_location_view_access(
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
    raise HTTPException(status_code=403, detail="No tienes permiso para ver esta ubicacion")


@router.get("/{freight_id}/live-location", response_model=DriverLiveLocationResponse)
def get_driver_live_location(
    freight_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    _require_live_location_view_access(freight, db, current_user)
    now = datetime.now(timezone.utc)
    response = _live_location_response(freight, now)
    if current_user.role == UserRole.client:
        record_audit_event(
            db,
            actor=current_user,
            entity_type="freight",
            entity_id=freight.id,
            event_type="freight.driver_location_viewed",
            request=request,
            metadata={"visible": response.visible, "is_stale": response.is_stale},
        )
        db.commit()
    return response


@router.put("/{freight_id}/live-location", response_model=DriverLiveLocationResponse)
def update_driver_live_location(
    freight_id: int,
    data: DriverLocationUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    check_rate_limit(
        request,
        scope="driver-live-location-update",
        identifier=f"{current_user.id}:{freight_id}",
        max_attempts=400,
        window_seconds=60 * 60,
    )
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    _require_assigned_driver(freight, db, current_user)

    now = datetime.now(timezone.utc)
    window_open, available_from = _live_location_window(freight, now)
    if not window_open:
        if available_from:
            raise HTTPException(
                status_code=409,
                detail="El seguimiento comienza cerca de la hora agendada",
            )
        raise HTTPException(
            status_code=409,
            detail="El seguimiento solo esta disponible durante un flete activo",
        )

    last_update = _as_utc(freight.driver_location_updated_at)
    if (
        last_update
        and (now - last_update).total_seconds()
        < settings.DRIVER_LOCATION_UPDATE_MIN_SECONDS
    ):
        raise HTTPException(status_code=429, detail="Actualiza tu ubicacion en unos segundos")

    freight.driver_location_lat = data.latitude
    freight.driver_location_lng = data.longitude
    freight.driver_location_accuracy_m = data.accuracy_m
    freight.driver_location_heading = data.heading
    freight.driver_location_updated_at = now
    db.commit()
    db.refresh(freight)
    return _live_location_response(freight, now)


@router.delete("/{freight_id}/live-location", status_code=204)
def stop_driver_live_location(
    freight_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    _require_assigned_driver(freight, db, current_user)
    _clear_live_location(freight)
    db.commit()


@router.get("/{freight_id}/cargo-photos")
def list_cargo_photo_view_urls(
    freight_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    freight = (
        db.query(FreightRequest)
        .options(selectinload(FreightRequest.cargo_photos), joinedload(FreightRequest.driver))
        .filter(FreightRequest.id == freight_id)
        .first()
    )
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    _require_cargo_photo_view_access(freight, current_user)
    base_url = (
        settings.PUBLIC_API_URL.rstrip("/")
        if settings.PUBLIC_API_URL
        else str(request.base_url).rstrip("/")
    )
    photos = []
    for photo in freight.cargo_photos:
        token, expires_at = create_cargo_photo_view_token(
            freight.id,
            photo.id,
            photo.object_ref,
        )
        photos.append(
            {
                "id": photo.id,
                "url": f"{base_url}/freights/cargo-photos/{token}",
                "expires_at": expires_at,
            }
        )
    return {"photos": photos}


@router.get("/cargo-photos/{token}", response_class=StreamingResponse)
def view_cargo_photo(token: str, db: Session = Depends(get_db)):
    payload = decode_cargo_photo_view_token(token)
    photo = (
        db.query(FreightCargoPhoto)
        .filter(
            FreightCargoPhoto.id == payload.get("photo_id"),
            FreightCargoPhoto.freight_id == payload.get("freight_id"),
        )
        .first()
    )
    if not photo or photo.object_ref != payload.get("photo_ref"):
        raise HTTPException(status_code=404, detail="Foto no disponible")
    return stream_private_document(photo.object_ref)


@router.post("/{freight_id}/delivery-pin", response_model=DeliveryPinResponse)
def generate_delivery_pin(
    freight_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client")),
):
    check_rate_limit(
        request,
        scope="freight-delivery-pin",
        identifier=f"{current_user.id}:{freight_id}",
        max_attempts=10,
        window_seconds=15 * 60,
    )
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
    check_rate_limit(
        request,
        scope="freight-evidence-upload",
        identifier=f"{current_user.id}:{freight_id}:{kind}",
        max_attempts=20,
        window_seconds=60 * 60,
    )
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
    if kind == "pickup" and not freight.driver_arrived_pickup_at:
        freight.driver_arrived_pickup_at = uploaded_at
    if kind == "delivery" and not freight.driver_arrived_destination_at:
        freight.driver_arrived_destination_at = uploaded_at
    freight.last_modified_by = current_user.id
    record_pricing_snapshot(
        db,
        freight,
        snapshot_type=(
            "driver_arrived_pickup"
            if kind == "pickup"
            else "driver_arrived_destination"
        ),
        captured_at=uploaded_at,
    )
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
def accept_freight(
    freight_id: int,
    data: FreightAcceptRequest | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver or driver.status != DriverStatus.approved:
        raise HTTPException(status_code=403, detail="Conductor no aprobado")
    require_driver_can_operate(driver)

    freight_candidate = (
        db.query(FreightRequest)
        .filter(
            FreightRequest.id == freight_id,
            FreightRequest.status == FreightStatus.pending,
            FreightRequest.driver_id.is_(None),
        )
        .first()
    )
    if not freight_candidate:
        raise HTTPException(status_code=400, detail="Flete no disponible")
    if (
        not freight_candidate.payment
        or freight_candidate.payment.status != PaymentStatus.authorized
    ):
        raise HTTPException(status_code=400, detail="El pago del cliente aun no esta confirmado")
    candidates = compatible_vehicles(driver, freight_candidate)
    if not candidates:
        raise HTTPException(status_code=403, detail="No tienes un vehiculo aprobado compatible")
    requested_vehicle_id = data.vehicle_id if data else None
    if requested_vehicle_id:
        vehicle = next(
            (item for item in candidates if item.id == requested_vehicle_id),
            None,
        )
        if not vehicle:
            raise HTTPException(status_code=403, detail="El vehiculo elegido no es compatible")
    else:
        vehicle = min(
            candidates,
            key=lambda item: (float(item.max_weight_kg or 0), item.id),
        )

    if (
        db.query(FreightDriverDecline.id)
        .filter(
            FreightDriverDecline.freight_id == freight_id,
            FreightDriverDecline.driver_id == driver.id,
        )
        .first()
    ):
        raise HTTPException(status_code=409, detail="Ya rechazaste este flete")

    accepted_at = datetime.now(timezone.utc)
    updated_rows = (
        db.query(FreightRequest)
        .filter(
            FreightRequest.id == freight_id,
            FreightRequest.status == FreightStatus.pending,
            FreightRequest.driver_id.is_(None),
        )
        .update(
            {
                FreightRequest.driver_id: driver.id,
                FreightRequest.status: FreightStatus.accepted,
                FreightRequest.accepted_at: accepted_at,
                FreightRequest.actual_vehicle_id: vehicle.id,
                FreightRequest.last_modified_by: current_user.id,
            },
            synchronize_session=False,
        )
    )
    if updated_rows != 1:
        db.rollback()
        raise HTTPException(status_code=400, detail="Flete no disponible")

    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    freight.driver_assigned_at = accepted_at
    freight.driver_accepted_at = accepted_at
    history = TripStatusHistory(freight_id=freight.id, status=FreightStatus.accepted, note=f"Aceptado por conductor {driver.id}")
    db.add(history)
    record_pricing_snapshot(
        db,
        freight,
        snapshot_type="driver_assigned",
        captured_at=accepted_at,
    )
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight",
        entity_id=freight.id,
        event_type="freight.accepted",
        before_data={"status": FreightStatus.pending.value, "driver_id": None},
        after_data={
            "status": FreightStatus.accepted.value,
            "driver_id": driver.id,
            "accepted_at": accepted_at.isoformat(),
            "actual_vehicle_id": vehicle.id,
        },
        metadata={"driver_profile_id": driver.id},
    )
    record_audit_event(
        db,
        actor=current_user,
        entity_type="freight",
        entity_id=freight.id,
        event_type="driver_assigned",
        after_data={
            "driver_id": driver.id,
            "actual_vehicle_id": freight.actual_vehicle_id,
        },
    )
    db.commit()
    db.refresh(freight)
    return freight


@router.post("/{freight_id}/decline", response_model=FreightDeclineResponse)
def decline_freight(
    freight_id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    driver = _get_driver_for_user(db, current_user)
    if not driver:
        raise HTTPException(status_code=403, detail="Perfil de conductor no encontrado")
    require_driver_can_operate(driver)
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    if freight.status != FreightStatus.pending or freight.driver_id is not None:
        raise HTTPException(status_code=409, detail="El flete ya no esta disponible")

    already_declined = (
        db.query(FreightDriverDecline.id)
        .filter(
            FreightDriverDecline.freight_id == freight.id,
            FreightDriverDecline.driver_id == driver.id,
        )
        .first()
    )
    if not already_declined:
        db.add(FreightDriverDecline(freight_id=freight.id, driver_id=driver.id))
        record_audit_event(
            db,
            actor=current_user,
            entity_type="freight",
            entity_id=freight.id,
            event_type="freight.declined",
            request=request,
            metadata={"driver_profile_id": driver.id},
        )
        db.commit()
    return FreightDeclineResponse(freight_id=freight.id, declined=True)

@router.put("/{freight_id}/status", response_model=FreightResponse)
def update_status(
    freight_id: int,
    data: FreightStatusUpdate,
    request: Request,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    check_rate_limit(
        request,
        scope="freight-status-update",
        identifier=f"{current_user.id}:{freight_id}",
        max_attempts=30,
        window_seconds=15 * 60,
    )
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
    transitioned_at = datetime.now(timezone.utc)
    freight.status = data.status
    if data.status == FreightStatus.in_progress:
        freight.started_at = transitioned_at
        freight.trip_started_at = transitioned_at
    elif data.status == FreightStatus.completed:
        freight.completed_at = transitioned_at
        freight.trip_completed_at = transitioned_at
        freight.final_price = freight.estimated_price
        freight.delivery_pin_verified_at = transitioned_at
        _clear_live_location(freight)
    elif data.status == FreightStatus.cancelled:
        freight.cancelled_at = transitioned_at
        freight.cancel_reason = data.note
        _clear_live_location(freight)
    freight.last_modified_by = current_user.id

    history = TripStatusHistory(freight_id=freight.id, status=data.status, note=data.note)
    db.add(history)
    snapshot_type = {
        FreightStatus.in_progress: "trip_started",
        FreightStatus.completed: "trip_completed",
        FreightStatus.cancelled: "trip_cancelled",
    }.get(data.status, "status_changed")
    record_pricing_snapshot(
        db,
        freight,
        snapshot_type=snapshot_type,
        captured_at=transitioned_at,
    )
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
    if snapshot_type != "status_changed":
        record_audit_event(
            db,
            actor=current_user,
            entity_type="freight",
            entity_id=freight.id,
            event_type=snapshot_type,
            after_data={
                "pricing_version": PRICING_VERSION,
                "estimated_customer_price": freight.estimated_price,
                "final_customer_price": freight.final_price,
                "actual_distance_km": freight.actual_distance_km,
            },
            request=request,
        )
    payout = None
    if data.status == FreightStatus.completed and freight.payment:
        payout = ensure_driver_payout(db, freight.payment)
        if payout:
            record_audit_event(
                db,
                actor=current_user,
                entity_type="driver_payout",
                entity_id=payout.id,
                event_type="driver_payout.created",
                after_data={
                    "payment_id": payout.payment_id,
                    "freight_id": payout.freight_id,
                    "driver_id": payout.driver_id,
                    "amount": payout.amount,
                    "status": payout.status.value,
                },
                request=request,
            )
    db.commit()
    db.refresh(freight)
    background_tasks.add_task(
        freight_chat_connections.broadcast,
        freight.id,
        {
            "type": "status",
            "status": data.status.value,
            "is_writable": data.status in CHAT_WRITABLE_STATUSES,
        },
    )
    return freight

@router.post("/estimate")
async def estimate_freight(
    request: Request,
    origin_lat: float = Query(..., ge=-90, le=90, allow_inf_nan=False),
    origin_lng: float = Query(..., ge=-180, le=180, allow_inf_nan=False),
    destination_lat: float = Query(..., ge=-90, le=90, allow_inf_nan=False),
    destination_lng: float = Query(..., ge=-180, le=180, allow_inf_nan=False),
    cargo_weight_kg: float = Query(..., gt=0, le=20_000, allow_inf_nan=False),
    cargo_volume_m3: Optional[float] = Query(None, gt=0, le=200, allow_inf_nan=False),
    requires_helpers: int = Query(0, ge=0, le=2),
    is_urgent:        bool = False,
    scheduled_at:     Optional[datetime] = None,
    current_user: User = Depends(require_role("client")),
):
    check_rate_limit(
        request,
        scope="freight-estimate",
        identifier=str(current_user.id),
        max_attempts=120,
        window_seconds=60 * 60,
    )
    from types import SimpleNamespace

    data = SimpleNamespace(
        origin_lat=origin_lat,
        origin_lng=origin_lng,
        destination_lat=destination_lat,
        destination_lng=destination_lng,
        cargo_weight_kg=cargo_weight_kg,
        cargo_volume_m3=cargo_volume_m3,
        cargo_description="Carga estandar",
        requires_helpers=requires_helpers,
        extra_stops=0,
        pickup_floor=None,
        delivery_floor=None,
        pickup_has_elevator=True,
        delivery_has_elevator=True,
        service_type=None,
        is_urgent=is_urgent,
        scheduled_at=scheduled_at,
        requested_vehicle_type=None,
    )
    try:
        map_data, prices = await calculate_pricing_estimate(
            data,
            request_id=getattr(request.state, "request_id", None),
        )
    except RouteCalculationError:
        raise HTTPException(
            status_code=503,
            detail="No pudimos calcular la tarifa en este momento. Intenta nuevamente.",
        )
    except PricingInputError as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    return {
        **prices,
        "distance_km": round(map_data["distance_km"], 2),
        "duration_minutes": map_data["duration_minutes"],
        "distance_text": map_data.get("distance_text"),
        "duration_text": map_data.get("duration_text"),
        "route_provider": map_data.get("provider"),
    }
