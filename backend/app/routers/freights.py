import secrets
from datetime import datetime, timezone
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
from app.database import SessionLocal, get_db
from app.models.driver import Driver, DriverStatus
from app.models.freight import FreightRequest, FreightStatus, TripStatusHistory
from app.models.pricing_quote import FreightPriceQuote
from app.models.user import User, UserRole
from app.schemas.freight import (
    DeliveryPinResponse,
    EvidenceViewResponse,
    FreightCreate,
    FreightCreateResponse,
    FreightResponse,
    FreightStatusUpdate,
)
from app.services.audit_service import record_audit_event
from app.services.driver_operational_service import require_driver_can_operate
from app.services.freight_service import (
    PRICING_VERSION,
    can_transition,
    normalize_service_type,
)
from app.services.cloud_tasks_service import enqueue_freight_driver_notification_task
from app.services.maps_service import RouteCalculationError
from app.services.pricing_estimate_service import calculate_pricing_estimate
from app.services.pricing_history_service import record_pricing_snapshot
from app.services.pricing_quote_service import consume_pricing_quote
from app.services.pricing_service import PricingInputError
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


async def _notify_available_drivers(title: str, body: str, data: dict) -> None:
    from app.services.notification_service import send_notification_to_drivers

    db = SessionLocal()
    try:
        await send_notification_to_drivers(
            db=db,
            title=title,
            body=body,
            data=data,
        )
    except Exception:
        print("[notifications] Could not notify available drivers")
    finally:
        db.close()


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

@router.post("", response_model=FreightCreateResponse, status_code=201)
async def create_freight(
    data: FreightCreate,
    request: Request,
    background_tasks: BackgroundTasks,
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

    if settings.ENABLE_DRIVER_PUSH_NOTIFICATIONS:
        notification_title = "Nuevo flete disponible"
        notification_body = (
            f"{'URGENTE' if data.is_urgent else 'Programado'} - "
            f"${prices['client_pays']:,.0f} CLP"
        )
        notification_data = {
            "freight_id": str(freight.id),
            "type": "new_freight",
            "mode": prices["mode"],
            "route": f"/app/driver/freights/{freight.id}",
        }
        if settings.NOTIFICATION_TASKS_ENABLED:
            background_tasks.add_task(
                enqueue_freight_driver_notification_task,
                freight_id=freight.id,
                title=notification_title,
                body=notification_body,
                data=notification_data,
            )
        else:
            background_tasks.add_task(
                _notify_available_drivers,
                title=notification_title,
                body=notification_body,
                data=notification_data,
            )
    return freight

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
        joinedload(FreightRequest.driver).joinedload(Driver.user),
        joinedload(FreightRequest.driver).joinedload(Driver.vehicle),
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
                query = query.filter(
                    FreightRequest.status == FreightStatus.pending,
                    FreightRequest.driver_id == None,
                )
        else:
            query = query.filter(FreightRequest.driver_id == driver.id) if driver else query.filter(False)
    if status and status != "available":
        query = query.filter(FreightRequest.status == status)
    return query.order_by(FreightRequest.created_at.desc()).all()

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
def accept_freight(freight_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_role("driver"))):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver or driver.status != DriverStatus.approved:
        raise HTTPException(status_code=403, detail="Conductor no aprobado")
    require_driver_can_operate(driver)

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
                FreightRequest.last_modified_by: current_user.id,
            },
            synchronize_session=False,
        )
    )
    if updated_rows != 1:
        db.rollback()
        raise HTTPException(status_code=400, detail="Flete no disponible")

    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    vehicle = driver.vehicle
    freight.actual_vehicle_id = vehicle.id if vehicle else None
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

@router.put("/{freight_id}/status", response_model=FreightResponse)
def update_status(
    freight_id: int,
    data: FreightStatusUpdate,
    request: Request,
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
    elif data.status == FreightStatus.cancelled:
        freight.cancelled_at = transitioned_at
        freight.cancel_reason = data.note
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
    db.commit()
    db.refresh(freight)
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
