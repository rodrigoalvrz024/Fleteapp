from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User
from app.models.driver import Driver
from app.models.freight import FreightRequest, FreightStatus
from app.models.rating import Rating
from app.models.payment import PaymentStatus
from app.schemas.rating import RatingCreate, RatingResponse
from app.core.security import require_role
from app.services.audit_service import record_audit_event

router = APIRouter(prefix="/ratings", tags=["Calificaciones"])

@router.post("", response_model=RatingResponse, status_code=201)
def create_rating(
    data: RatingCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client")),
):
    freight = db.query(FreightRequest).filter(
        FreightRequest.id == data.freight_id,
        FreightRequest.client_id == current_user.id,
        FreightRequest.status == FreightStatus.completed
    ).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado o no completado")
    if freight.rating:
        raise HTTPException(status_code=400, detail="Ya calificaste este servicio")
    if not freight.payment or freight.payment.status != PaymentStatus.authorized:
        raise HTTPException(
            status_code=400,
            detail="Debes completar el pago antes de calificar",
        )

    rating = Rating(
        freight_id=data.freight_id,
        rater_id=current_user.id,
        rated_driver_id=freight.driver_id,
        score=data.score,
        comment=data.comment,
    )
    db.add(rating)

    driver = db.query(Driver).filter(Driver.id == freight.driver_id).first()
    if driver:
        total = driver.rating_average * driver.rating_count + data.score
        driver.rating_count += 1
        driver.rating_average = round(total / driver.rating_count, 2)

    db.flush()
    record_audit_event(
        db,
        actor=current_user,
        entity_type="rating",
        entity_id=rating.id,
        event_type="rating.created",
        after_data={
            "freight_id": freight.id,
            "driver_id": freight.driver_id,
            "score": data.score,
        },
        request=request,
    )
    db.commit()
    db.refresh(rating)
    return rating
