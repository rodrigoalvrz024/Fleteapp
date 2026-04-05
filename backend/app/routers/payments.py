from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from datetime import datetime
from app.database import get_db
from app.models.user import User
from app.models.freight import FreightRequest, FreightStatus
from app.models.payment import Payment, PaymentStatus, PaymentMethod
from app.schemas.payment import PaymentCreate, PaymentResponse, WebpayInitResponse
from app.core.security import require_role
from app.core.config import settings
import uuid

router = APIRouter(prefix="/payments", tags=["Pagos"])

@router.post("/initiate", response_model=WebpayInitResponse)
def initiate_payment(data: PaymentCreate, db: Session = Depends(get_db), current_user: User = Depends(require_role("client"))):
    freight = db.query(FreightRequest).filter(
        FreightRequest.id == data.freight_id,
        FreightRequest.client_id == current_user.id,
        FreightRequest.status == FreightStatus.completed
    ).first()
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado o no completado")

    if freight.payment and freight.payment.status == PaymentStatus.authorized:
        raise HTTPException(status_code=400, detail="Este flete ya fue pagado")

    buy_order = f"FLETE-{freight.id}-{uuid.uuid4().hex[:8].upper()}"
    amount = int(freight.final_price or freight.estimated_price)

    # Modo sandbox Transbank — en producción usar el SDK oficial
    payment = Payment(
        freight_id=freight.id,
        amount=amount,
        method=data.method,
        buy_order=buy_order,
        status=PaymentStatus.pending,
        webpay_token=f"SANDBOX_TOKEN_{buy_order}",
    )
    db.add(payment)
    db.commit()

    # URL simulada para sandbox
    webpay_url = f"https://webpay3gint.transbank.cl/webpayserver/initTransaction?token_ws={payment.webpay_token}"
    return WebpayInitResponse(token=payment.webpay_token, url=webpay_url)

@router.post("/callback")
def payment_callback(token_ws: str = None, db: Session = Depends(get_db)):
    if not token_ws:
        raise HTTPException(status_code=400, detail="Token requerido")
    payment = db.query(Payment).filter(Payment.webpay_token == token_ws).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    payment.status = PaymentStatus.authorized
    payment.paid_at = datetime.utcnow()
    payment.authorization_code = f"AUTH-{uuid.uuid4().hex[:6].upper()}"
    db.commit()
    return {"message": "Pago confirmado", "payment_id": payment.id}

@router.get("/{payment_id}", response_model=PaymentResponse)
def get_payment(payment_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_role("client"))):
    payment = db.query(Payment).filter(Payment.id == payment_id).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    return payment