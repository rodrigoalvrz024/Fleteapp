"""Structured bilateral feedback after a completed freight."""

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.core.security import require_role
from app.database import get_db
from app.models.driver import Driver
from app.models.freight import FreightRequest, FreightStatus, TripFeedback
from app.models.rating import Rating
from app.models.user import User, UserRole
from app.schemas.feedback import TripFeedbackCreate, TripFeedbackResponse
from app.services.audit_service import record_audit_event


router = APIRouter(prefix="/feedback", tags=["Evaluaciones"])

CLIENT_QUESTIONS = {
    "punctuality": "Puntualidad",
    "cargo_care": "Cuidado de la carga",
    "communication": "Comunicacion",
    "vehicle_condition": "Estado del vehiculo",
    "price_clarity": "Claridad del servicio",
}
DRIVER_QUESTIONS = {
    "communication": "Comunicacion",
    "pickup_readiness": "Carga lista para retirar",
    "address_access": "Acceso al origen y destino",
    "cargo_accuracy": "Descripcion de la carga",
    "respect": "Trato respetuoso",
}


def _freight_for_participant(db: Session, freight_id: int, user: User) -> tuple[FreightRequest, str, dict[str, str]]:
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight or freight.status != FreightStatus.completed:
        raise HTTPException(status_code=404, detail="Flete no encontrado o no completado")

    if user.role == UserRole.client and freight.client_id == user.id:
        return freight, "driver", CLIENT_QUESTIONS
    if user.role == UserRole.driver and freight.driver and freight.driver.user_id == user.id:
        return freight, "client", DRIVER_QUESTIONS
    raise HTTPException(status_code=403, detail="No tienes permiso para evaluar este flete")


@router.get("/freights/{freight_id}")
def get_my_feedback(
    freight_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client", "driver")),
):
    freight, recipient_role, questions = _freight_for_participant(db, freight_id, current_user)
    feedback = (
        db.query(TripFeedback)
        .filter(TripFeedback.freight_id == freight.id, TripFeedback.rater_id == current_user.id)
        .first()
    )
    return {
        "recipient_role": recipient_role,
        "questions": [
            {"key": key, "label": label}
            for key, label in questions.items()
        ],
        "feedback": TripFeedbackResponse.model_validate(feedback).model_dump(mode="json") if feedback else None,
    }


@router.post("/freights/{freight_id}", response_model=TripFeedbackResponse, status_code=201)
def create_trip_feedback(
    freight_id: int,
    data: TripFeedbackCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client", "driver")),
):
    freight, recipient_role, questions = _freight_for_participant(db, freight_id, current_user)
    if set(data.answers) != set(questions):
        raise HTTPException(status_code=422, detail="Responde todas las preguntas de la evaluacion")
    if (
        db.query(TripFeedback)
        .filter(TripFeedback.freight_id == freight.id, TripFeedback.rater_id == current_user.id)
        .first()
    ):
        raise HTTPException(status_code=409, detail="Ya enviaste tu evaluacion")

    feedback = TripFeedback(
        freight_id=freight.id,
        rater_id=current_user.id,
        recipient_role=recipient_role,
        overall_score=data.overall_score,
        answers=data.answers,
        comment=data.comment.strip() if data.comment else None,
    )
    db.add(feedback)

    # Preserve the existing public driver rating while adding the richer form.
    if recipient_role == "driver" and freight.driver_id and not freight.rating:
        rating = Rating(
            freight_id=freight.id,
            rater_id=current_user.id,
            rated_driver_id=freight.driver_id,
            score=data.overall_score,
            comment=feedback.comment,
        )
        db.add(rating)
        driver = db.query(Driver).filter(Driver.id == freight.driver_id).first()
        if driver:
            total = float(driver.rating_average or 0) * int(driver.rating_count or 0) + data.overall_score
            driver.rating_count = int(driver.rating_count or 0) + 1
            driver.rating_average = round(total / driver.rating_count, 2)

    db.flush()
    record_audit_event(
        db,
        actor=current_user,
        entity_type="trip_feedback",
        entity_id=feedback.id,
        event_type="trip_feedback.created",
        after_data={
            "freight_id": freight.id,
            "recipient_role": recipient_role,
            "overall_score": data.overall_score,
            "answer_keys": sorted(data.answers),
        },
        request=request,
    )
    db.commit()
    db.refresh(feedback)
    return feedback
