from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile
from sqlalchemy.orm import Session

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
from app.services.storage_service import upload_driver_document

router = APIRouter(prefix="/drivers", tags=["Conductores"])

DOCUMENT_FIELDS = {
    "profile_image": "profile_image_url",
    "license_image": "license_image_url",
    "vehicle_doc": "vehicle_doc_url",
    "circulation_permit": "circulation_permit_url",
    "technical_review": "technical_review_url",
    "soap": "soap_url",
}


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
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("driver")),
):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Perfil de conductor no encontrado")
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
        "license_number": driver.license_number,
        "license_expiry": driver.license_expiry.isoformat()
        if driver.license_expiry
        else None,
    }
    for field, value in data.model_dump(exclude_none=True).items():
        setattr(driver, field, value)
    driver.last_modified_by = current_user.id
    record_audit_event(
        db,
        actor=current_user,
        entity_type="driver",
        entity_id=driver.id,
        event_type="driver.updated",
        before_data=before_data,
        after_data=data.model_dump(exclude_none=True, mode="json"),
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

    url = await upload_driver_document(selected_file, driver.id, selected_field)
    setattr(driver, DOCUMENT_FIELDS[selected_field], url)
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
        },
        request=request,
    )
    db.commit()

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
    if not driver.technical_review_url:
        raise HTTPException(status_code=400, detail="Debes subir la revision tecnica")
    if not driver.soap_url:
        raise HTTPException(status_code=400, detail="Debes subir el SOAP")

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
