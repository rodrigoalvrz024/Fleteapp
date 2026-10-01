from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.rate_limit import check_rate_limit
from app.core.security import get_current_user, require_role
from app.database import get_db
from app.models.support_faq import SupportFAQ
from app.models.user import User
from app.schemas.support_faq import FAQResponse, FAQUpdate, FAQWrite
from app.services.audit_service import record_audit_event

router = APIRouter(prefix="/support", tags=["Ayuda"])


def _limit(request, user, scope, count):
    check_rate_limit(request, scope=scope, identifier=str(user.id),
                     max_attempts=count, window_seconds=60)


@router.get("/faqs", response_model=list[FAQResponse])
def list_faqs(request: Request, offset: int = Query(0, ge=0, le=10000),
              limit: int = Query(100, ge=1, le=100),
              db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    _limit(request, user, "support-read", 60)
    role = user.role.value if hasattr(user.role, "value") else str(user.role)
    query = db.query(SupportFAQ).filter(SupportFAQ.published.is_(True))
    if role != "admin":
        query = query.filter(SupportFAQ.audience.in_(["all", role]))
    return query.order_by(SupportFAQ.sort_order, SupportFAQ.id).offset(offset).limit(limit).all()


@router.get("/admin/faqs", response_model=list[FAQResponse])
def admin_faqs(request: Request, offset: int = Query(0, ge=0, le=10000),
               limit: int = Query(100, ge=1, le=100), db: Session = Depends(get_db),
               user: User = Depends(require_role("admin"))):
    _limit(request, user, "support-admin-read", 60)
    return db.query(SupportFAQ).order_by(SupportFAQ.sort_order, SupportFAQ.id).offset(offset).limit(limit).all()


def _commit(db):
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Ya existe una pregunta con ese identificador") from None
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(503, "No pudimos guardar la respuesta. Intenta nuevamente.") from None


@router.post("/admin/faqs", response_model=FAQResponse, status_code=201)
def create_faq(data: FAQWrite, request: Request, db: Session = Depends(get_db),
               user: User = Depends(require_role("admin"))):
    _limit(request, user, "support-admin-write", 30)
    entry = SupportFAQ(**data.model_dump())
    db.add(entry)
    # Audit and content commit together; use the stable slug before ID allocation.
    record_audit_event(db, actor=user, entity_type="support_faq", entity_id=data.slug,
                       event_type="support.faq_created", after_data=data.model_dump(), request=request)
    _commit(db)
    db.refresh(entry)
    return entry


@router.put("/admin/faqs/{faq_id}", response_model=FAQResponse)
def update_faq(faq_id: int, data: FAQUpdate, request: Request,
               db: Session = Depends(get_db), user: User = Depends(require_role("admin"))):
    _limit(request, user, "support-admin-write", 30)
    entry = db.query(SupportFAQ).filter(SupportFAQ.id == faq_id).first()
    if not entry:
        raise HTTPException(404, "Pregunta no disponible")
    if entry.version != data.version:
        raise HTTPException(409, "La respuesta cambió. Recarga antes de guardar.")
    before = FAQResponse.model_validate(entry).model_dump(mode="json")
    values = data.model_dump(exclude={"version"})
    values.update(version=data.version + 1, updated_at=datetime.now(timezone.utc))
    try:
        count = db.query(SupportFAQ).filter(SupportFAQ.id == faq_id,
            SupportFAQ.version == data.version).update(values, synchronize_session=False)
        if count != 1:
            db.rollback()
            raise HTTPException(409, "La respuesta cambió. Recarga antes de guardar.")
        record_audit_event(db, actor=user, entity_type="support_faq", entity_id=faq_id,
                           event_type="support.faq_updated", before_data=before,
                           after_data=data.model_dump(), request=request)
        _commit(db)
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Ya existe una pregunta con ese identificador") from None
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(503, "No pudimos guardar la respuesta. Intenta nuevamente.") from None
    db.refresh(entry)
    return entry
