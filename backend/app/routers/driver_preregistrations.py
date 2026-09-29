from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.launch_rate_limit import check_rate_limit
from app.database import get_db
from app.models.driver_preregistration import DriverPreregistration
from app.schemas.driver_preregistration import DriverPreregistrationCreate, CONSENT_VERSION
from app.services.preregistration_sheets import sync_preregistration

router = APIRouter(prefix="/public/driver-preregistrations", tags=["Preinscripciones"])


@router.post("", status_code=202)
def preregister_driver(data: DriverPreregistrationCreate, request: Request,
                      background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    if not settings.DRIVER_PREREGISTRATION_ENABLED:
        raise HTTPException(503, "La preinscripción todavía no está habilitada. Escríbenos a soporte@muvv.cl.")
    check_rate_limit(request, scope="driver-preregistration", max_attempts=5, window_seconds=3600)
    accepted = {"status": "received"}
    # No public lookup or disclosure of whether an email is already registered.
    if data.website:
        return accepted
    if db.query(DriverPreregistration.id).filter_by(email=data.email).first():
        return accepted
    entry = DriverPreregistration(
        **data.model_dump(exclude={"website", "consent_version"}),
        consent_version=CONSENT_VERSION,
    )
    try:
        db.add(entry)
        db.flush()
        entry_id = entry.id
        db.commit()
    except IntegrityError:
        db.rollback()
        if db.query(DriverPreregistration.id).filter_by(email=data.email).first():
            return accepted
        raise HTTPException(503, "No pudimos guardar tu preinscripción. Intenta nuevamente.") from None
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(503, "No pudimos guardar tu preinscripción. Intenta nuevamente.") from None
    # Sheets failures cannot roll back a successfully saved registration.
    background_tasks.add_task(sync_preregistration, entry_id)
    return accepted
