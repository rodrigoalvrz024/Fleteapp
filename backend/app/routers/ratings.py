from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User
from app.models.driver import Driver
from app.models.freight import FreightRequest, FreightStatus
from app.models.rating import Rating
from app.schemas.rating import RatingCreate, RatingResponse
from app.core.security import require_role

router = APIRouter(prefix="/ratings", tags=["Calificaciones"])

@router.post("", response_model=RatingResponse, status_code=201)
def create_rating(data: RatingCreate, db: Session = Depends(get_db), current_user: User = Depends(require_role("client"))):
    freight = db.query(FreightRequest).filter(
        FreightRequest.id == data.freight_id,
        FreightRequest.client_id == current_user.id,
        FreightRequest.status == FreightStatus.completed
    ).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado o no completado")
    if freight.rating:
        raise HTTPException(status_code=400, detail="Ya calificaste este servicio")

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

    db.commit()
    db.refresh(rating)
    return rating