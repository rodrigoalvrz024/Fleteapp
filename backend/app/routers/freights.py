from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime
from app.database import get_db
from app.models.user import User, UserRole
from app.models.driver import Driver
from app.models.freight import FreightRequest, FreightStatus, TripStatusHistory
from app.schemas.freight import FreightCreate, FreightResponse, FreightStatusUpdate
from app.core.security import get_current_user, require_role
from app.services.freight_service import calculate_distance_km, estimate_price, can_transition
from app.services.notification_service import send_push_notification
import asyncio

router = APIRouter(prefix="/freights", tags=["Fletes"])

@router.post("", response_model=FreightResponse, status_code=201)
def create_freight(data: FreightCreate, db: Session = Depends(get_db), current_user: User = Depends(require_role("client"))):
    dist = calculate_distance_km(data.origin_lat, data.origin_lng, data.destination_lat, data.destination_lng)
    price = estimate_price(dist, data.cargo_weight_kg, data.requires_helpers)

    freight = FreightRequest(
        client_id=current_user.id,
        distance_km=round(dist, 2),
        estimated_price=price,
        **data.model_dump()
    )
    db.add(freight)
    db.commit()
    db.refresh(freight)

    history = TripStatusHistory(freight_id=freight.id, status=FreightStatus.pending, note="Solicitud creada")
    db.add(history)
    db.commit()
    db.refresh(freight)
    return freight

@router.get("", response_model=List[FreightResponse])
def list_freights(status: str = None, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    query = db.query(FreightRequest)
    if current_user.role == UserRole.client:
        query = query.filter(FreightRequest.client_id == current_user.id)
    elif current_user.role == UserRole.driver:
        driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
        if status == "available":
            query = query.filter(FreightRequest.status == FreightStatus.pending, FreightRequest.driver_id == None)
        else:
            query = query.filter(FreightRequest.driver_id == driver.id) if driver else query.filter(False)
    if status and status != "available":
        query = query.filter(FreightRequest.status == status)
    return query.order_by(FreightRequest.created_at.desc()).all()

@router.get("/{freight_id}", response_model=FreightResponse)
def get_freight(freight_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    return freight

@router.put("/{freight_id}/accept", response_model=FreightResponse)
def accept_freight(freight_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_role("driver"))):
    driver = db.query(Driver).filter(Driver.user_id == current_user.id).first()
    if not driver or driver.status != "approved":
        raise HTTPException(status_code=403, detail="Conductor no aprobado")

    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight or freight.status != FreightStatus.pending:
        raise HTTPException(status_code=400, detail="Flete no disponible")

    freight.driver_id = driver.id
    freight.status = FreightStatus.accepted
    freight.accepted_at = datetime.utcnow()

    history = TripStatusHistory(freight_id=freight.id, status=FreightStatus.accepted, note=f"Aceptado por conductor {driver.id}")
    db.add(history)
    db.commit()
    db.refresh(freight)
    return freight

@router.put("/{freight_id}/status", response_model=FreightResponse)
def update_status(freight_id: int, data: FreightStatusUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    freight = db.query(FreightRequest).filter(FreightRequest.id == freight_id).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")

    if not can_transition(freight.status, data.status):
        raise HTTPException(status_code=400, detail=f"No se puede pasar de {freight.status} a {data.status}")

    freight.status = data.status
    if data.status == FreightStatus.in_progress:
        freight.started_at = datetime.utcnow()
    elif data.status == FreightStatus.completed:
        freight.completed_at = datetime.utcnow()
        freight.final_price = freight.estimated_price
    elif data.status == FreightStatus.cancelled:
        freight.cancelled_at = datetime.utcnow()
        freight.cancel_reason = data.note

    history = TripStatusHistory(freight_id=freight.id, status=data.status, note=data.note)
    db.add(history)
    db.commit()
    db.refresh(freight)
    return freight

from app.services.maps_service import get_distance_and_duration
from app.services.freight_service import estimate_price

@router.post("/estimate")
async def estimate_freight(
    origin_lat: float,
    origin_lng: float,
    destination_lat: float,
    destination_lng: float,
    cargo_weight_kg: float,
    requires_helpers: int = 0,
    current_user=Depends(get_current_user)
):
    """Estima precio antes de crear el flete."""
    data = await get_distance_and_duration(origin_lat, origin_lng, destination_lat, destination_lng)
    price = estimate_price(data["distance_km"], cargo_weight_kg, requires_helpers)
    return {
        "distance_km": round(data["distance_km"], 2),
        "duration_minutes": data["duration_minutes"],
        "distance_text": data.get("distance_text"),
        "duration_text": data.get("duration_text"),
        "estimated_price_clp": price,
    }