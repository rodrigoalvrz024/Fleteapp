from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile
from sqlalchemy.orm import Session

from app.core.rate_limit import check_rate_limit
from app.core.security import get_current_user, require_role
from app.database import get_db
from app.models.driver import Driver, DriverStatus
from app.models.user import User, UserRole
from app.models.vehicle import Vehicle
from app.schemas.driver import (
    DriverCreate,
    DriverResponse,
    DriverUpdate,
    VehicleCreate,
    VehicleResponse,
)
from app.services.audit_service import record_audit_event
from app.services.driver_operational_service import require_driver_can_operate
from app.services.storage_service import delete_private_document, upload_driver_document

router = APIRouter(prefix="/drivers", tags=["Conductores"])

DOCUMENT_FIELDS = {
    "profile_image": "profile_image_url",
    "license_image": "license_image_url",
    "vehicle_doc": "vehicle_doc_url",
    "circulation_permit": "circulation_permit_url",
    "technical_review": "technical_review_url",
    "soap": "soap_url",
}

DOCUMENT_EXPIRY_FIELDS = {
    "license_image": "license_expiry",
    "vehicle_doc": "vehicle_doc_expiry",
    "circulation_permit": "circulation_permit_expiry",
    "technical_review": "technical_review_expiry",
    "soap": "soap_expiry",
}

REVIEW_REQUIRED_UPDATE_FIELDS = {
    "license_number",
    "license_expiry",
    "vehicle_doc_expiry",
    "circulation_permit_expiry",
    "technical_review_expiry",
    "soap_expiry",
}


def _parse_optional_datetime(value) -> datetime | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(status_code=422, detail="Fecha de vencimiento invalida")


@router.post("/register", response_model=DriverResponse, status_code=201)
def register_driver(
    data: DriverCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.driver:
        raise HTTPException(status_code=403, detail="Solo conductores pueden registrarse aqui")
    if db.query(Driver).filter(Driver.user_id == current_user.id).first():
        raise HTTPException(status_code=400, detail="Ya tienes un perfil de conductor")
    driver = Driver(
        user_id=current_user.id,
        last_modified_by=current_user.id,
        **data.model_dump(),
    )
    db.add(driver)
    db.flush()
    record_audit_event(
        db,
        actor=current_user,
        entity_type="driver",
        entity_id=driver.id,
        event_type="driver.registered",
        after_data={"status": DriverStatus.pending.value},
        request=request,
    )
    db.commit()
    db.refresh(driver)
    return driver


@router.get("/me", response_model=DriverResponse)
def get_driver_profile(
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Perfil de conductor no encontrado")
    record_audit_event(
        db,
        actor=current_user,
        entity_type="driver",
        entity_id=driver.id,
        event_type="app.driver_profile_view",
        request=request,
        metadata={
            "driver_status": driver.status.value
            if hasattr(driver.status, "value")
            else str(driver.status),
            "is_available": driver.is_available,
            "has_vehicle": driver.vehicle is not None,
            "rating_average": driver.rating_average,
            "rating_count": driver.rating_count,
            "total_trips": driver.total_trips,
        },
    )
    db.commit()
    return driver


@router.put("/me", response_model=DriverResponse)
def update_driver(
    data: DriverUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Perfil no encontrado")
    before_data = {
        "is_available": driver.is_available,
        "status": driver.status.value if hasattr(driver.status, "value") else str(driver.status),
        "license_number": driver.license_number,
        "license_expiry": driver.license_expiry.isoformat()
        if driver.license_expiry
        else None,
    }
    if data.is_available is True:
        require_driver_can_operate(driver)
    update_data = data.model_dump(exclude_none=True)
    requires_reverification = (
        driver.status == DriverStatus.approved
        and any(field in REVIEW_REQUIRED_UPDATE_FIELDS for field in update_data)
    )
    for field, value in update_data.items():
        setattr(driver, field, value)
    if requires_reverification:
        driver.status = DriverStatus.pending
        driver.is_available = False
        driver.submitted_at = None
    driver.last_modified_by = current_user.id
    record_audit_event(
        db,
        actor=current_user,
        entity_type="driver",
        entity_id=driver.id,
        event_type="driver.updated",
        before_data=before_data,
        after_data={
            **data.model_dump(exclude_none=True, mode="json"),
            "status": driver.status.value if hasattr(driver.status, "value") else str(driver.status),
            "reverification_required": requires_reverification,
        },
        request=request,
    )
    db.commit()
    db.refresh(driver)
    return driver


@router.post("/vehicle", response_model=VehicleResponse, status_code=201)
def add_vehicle(
    data: VehicleCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Primero registrate como conductor")
    if driver.vehicle:
        raise HTTPException(status_code=400, detail="Ya tienes un vehiculo registrado")
    vehicle = Vehicle(
        driver_id=driver.id,
        last_modified_by=current_user.id,
        **data.model_dump(),
    )
    db.add(vehicle)
    db.flush()
    record_audit_event(
        db,
        actor=current_user,
        entity_type="vehicle",
        entity_id=vehicle.id,
        event_type="vehicle.created",
        after_data=data.model_dump(mode="json"),
        request=request,
        metadata={"driver_id": driver.id},
    )
    db.commit()
    db.refresh(vehicle)
    return vehicle


@router.post("/me/upload")
async def upload_driver_file(
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Perfil de conductor no encontrado")
    check_rate_limit(
        request,
        scope="driver-document-upload",
        identifier=str(current_user.id),
        max_attempts=30,
        window_seconds=60 * 60,
    )

    form = await request.form()
    selected_field = None
    selected_file = None
    for field in DOCUMENT_FIELDS:
        value = form.get(field)
        if isinstance(value, UploadFile) or (
            hasattr(value, "filename") and hasattr(value, "read")
        ):
            selected_field = field
            selected_file = value
            break

    if not selected_field or not selected_file:
        raise HTTPException(status_code=400, detail="Archivo no recibido")

    previous_ref = getattr(driver, DOCUMENT_FIELDS[selected_field], None)
    url = await upload_driver_document(selected_file, driver.id, selected_field)
    setattr(driver, DOCUMENT_FIELDS[selected_field], url)
    expiry_field = DOCUMENT_EXPIRY_FIELDS.get(selected_field)
    expiry_value = _parse_optional_datetime(
        form.get(f"{selected_field}_expiry") or form.get("expires_at")
    )
    if expiry_field and expiry_value:
        setattr(driver, expiry_field, expiry_value)
    requires_reverification = (
        selected_field != "profile_image"
        and driver.status == DriverStatus.approved
    )
    if requires_reverification:
        driver.status = DriverStatus.pending
        driver.is_available = False
        driver.submitted_at = None
    driver.last_modified_by = current_user.id
    record_audit_event(
        db,
        actor=current_user,
        entity_type="driver",
        entity_id=driver.id,
        event_type="driver.document_uploaded",
        after_data={
            "document_type": selected_field,
            "content_type": selected_file.content_type,
            "expiry_field": expiry_field,
            "expires_at": expiry_value.isoformat() if expiry_value else None,
            "reverification_required": requires_reverification,
        },
        request=request,
    )
    db.commit()

    if previous_ref and previous_ref != url:
        try:
            delete_private_document(previous_ref)
        except HTTPException:
            pass

    return {"field": selected_field, "url": url}


@router.put("/me/submit", response_model=DriverResponse)
def submit_driver_for_review(
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Perfil de conductor no encontrado")
    if not driver.vehicle:
        raise HTTPException(status_code=400, detail="Debes registrar un vehiculo")
    if not driver.license_image_url:
        raise HTTPException(status_code=400, detail="Debes subir tu licencia de conducir")
    if not (driver.vehicle_doc_url or driver.circulation_permit_url):
        raise HTTPException(status_code=400, detail="Debes subir el permiso de circulacion")
    if not (driver.vehicle_doc_expiry or driver.circulation_permit_expiry):
        raise HTTPException(
            status_code=400,
            detail="Debes registrar el vencimiento del permiso de circulacion",
        )
    if not driver.technical_review_url:
        raise HTTPException(status_code=400, detail="Debes subir la revision tecnica")
    if not driver.technical_review_expiry:
        raise HTTPException(
            status_code=400,
            detail="Debes registrar el vencimiento de la revision tecnica",
        )
    if not driver.soap_url:
        raise HTTPException(status_code=400, detail="Debes subir el SOAP")
    if not driver.soap_expiry:
        raise HTTPException(status_code=400, detail="Debes registrar el vencimiento del SOAP")

    status_before = driver.status.value if hasattr(driver.status, "value") else str(driver.status)
    driver.status = DriverStatus.pending
    driver.is_available = False
    driver.submitted_at = datetime.now(timezone.utc)
    driver.rejection_reason = None
    driver.last_modified_by = current_user.id
    record_audit_event(
        db,
        actor=current_user,
        entity_type="driver",
        entity_id=driver.id,
        event_type="driver.submitted_for_review",
        before_data={"status": status_before},
        after_data={
            "status": DriverStatus.pending.value,
            "submitted_at": driver.submitted_at.isoformat(),
        },
        request=request,
    )
    db.commit()
    db.refresh(driver)
    return driver
