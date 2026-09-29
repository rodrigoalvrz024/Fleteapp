from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.launch_rate_limit import check_rate_limit
from app.database import get_db
from app.models.launch_signup import LaunchSignup
from app.schemas.launch_signup import LaunchSignupCreate, CONSENT_VERSION
from app.services.preregistration_sheets import sync_launch_signup

router = APIRouter(prefix="/public/launch-signups", tags=["Lanzamiento"])


@router.post("", status_code=202)
def subscribe_launch(data: LaunchSignupCreate, request: Request,
                      background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    if not settings.LAUNCH_SIGNUP_ENABLED:
        raise HTTPException(503, "La inscripción todavía no está habilitada. Escríbenos a soporte@muvv.cl.")
    check_rate_limit(request, scope="launch-signup", max_attempts=5, window_seconds=3600)
    accepted = {"status": "received"}
    # No public lookup or disclosure of whether an email is already registered.
    if data.website:
        return accepted
    if db.query(LaunchSignup.id).filter_by(email=data.email).first():
        return accepted
    entry = LaunchSignup(
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
        if db.query(LaunchSignup.id).filter_by(email=data.email).first():
            return accepted
        raise HTTPException(503, "No pudimos guardar tu inscripción. Intenta nuevamente.") from None
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(503, "No pudimos guardar tu inscripción. Intenta nuevamente.") from None
    # Sheets failures cannot roll back a successfully saved registration.
    background_tasks.add_task(sync_launch_signup, entry_id)
    return accepted
