import html
import uuid
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from datetime import datetime, timezone
from app.database import get_db
from app.models.user import User, UserRole
from app.models.freight import FreightRequest, FreightStatus
from app.models.payment import Payment, PaymentStatus, PaymentMethod
from app.schemas.payment import PaymentCreate, PaymentResponse, WebpayInitResponse
from app.core.rate_limit import check_rate_limit
from app.core.security import get_current_user, require_role
from app.core.config import settings
from app.services.audit_service import record_audit_event
from app.services.payout_service import ensure_driver_payout
from app.services.transbank_service import (
    commit_webpay_transaction,
    create_webpay_transaction,
)
router = APIRouter(prefix="/payments", tags=["Pagos"])


def _frontend_payment_result(freight_id: int, result: str) -> str:
    return (
        f"{settings.FRONTEND_URL.rstrip('/')}/#/app/client/freights/"
        f"{freight_id}?payment={result}"
    )

@router.post("/initiate", response_model=WebpayInitResponse)
def initiate_payment(
    data: PaymentCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client")),
):
    check_rate_limit(
        request,
        scope="payment-initiate",
        identifier=f"{current_user.id}:{data.freight_id}",
        max_attempts=10,
        window_seconds=15 * 60,
    )
    if data.method != PaymentMethod.webpay:
        raise HTTPException(
            status_code=400,
            detail="Por ahora solo Webpay esta habilitado para pagos en app",
        )
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
    payment = freight.payment or Payment(freight_id=freight.id)
    payment.amount = amount
    payment.method = data.method
    payment.buy_order = buy_order
    payment.status = PaymentStatus.pending
    payment.webpay_token = None
    payment.authorization_code = None
    payment.transaction_id = None
    payment.paid_at = None
    payment.last_modified_by = current_user.id
    if not freight.payment:
        db.add(payment)
    db.flush()

    base_url = (
        settings.PUBLIC_API_URL.rstrip("/")
        if settings.PUBLIC_API_URL
        else str(request.base_url).rstrip("/")
    )
    return_url = f"{base_url}/payments/callback"
    if settings.ALLOW_SIMULATED_PAYMENTS:
        webpay_token = f"SANDBOX_TOKEN_{buy_order}"
        webpay_url = (
            "https://webpay3gint.transbank.cl/webpayserver/initTransaction"
            f"?token_ws={webpay_token}"
        )
    else:
        webpay = create_webpay_transaction(
            buy_order=buy_order,
            session_id=f"user-{current_user.id}",
            amount=amount,
            return_url=return_url,
        )
        webpay_token = webpay.token
        webpay_url = webpay.url

    payment.webpay_token = webpay_token
    redirect_url = (
        f"{return_url}?token_ws={webpay_token}"
        if settings.ALLOW_SIMULATED_PAYMENTS and webpay_token.startswith("SANDBOX_TOKEN_")
        else f"{base_url}/payments/webpay/{webpay_token}"
    )
    record_audit_event(
        db,
        actor=current_user,
        entity_type="payment",
        entity_id=payment.id,
        event_type="payment.initiated",
        after_data={
            "freight_id": freight.id,
            "amount": amount,
            "method": data.method.value,
            "status": PaymentStatus.pending.value,
        },
    )
    db.commit()

    return WebpayInitResponse(
        token=payment.webpay_token,
        url=webpay_url,
        redirect_url=redirect_url,
    )


@router.get("/webpay/{token_ws}", response_class=HTMLResponse)
def redirect_to_webpay(token_ws: str, db: Session = Depends(get_db)):
    payment = db.query(Payment).filter(Payment.webpay_token == token_ws).first()
    if not payment or payment.status != PaymentStatus.pending:
        raise HTTPException(status_code=404, detail="Pago no disponible")
    action = html.escape(payment_redirect_url(), quote=True)
    token = html.escape(token_ws, quote=True)
    return HTMLResponse(
        content=f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Conectando con Webpay</title></head>
<body>
  <p>Conectando con Webpay...</p>
  <form id="webpay" method="post" action="{action}">
    <input type="hidden" name="token_ws" value="{token}">
  </form>
  <script>document.getElementById('webpay').submit();</script>
</body></html>""",
        headers={"Cache-Control": "no-store"},
    )


def payment_redirect_url() -> str:
    if settings.TRANSBANK_ENVIRONMENT.lower() == "production":
        return "https://webpay3g.transbank.cl/webpayserver/initTransaction"
    return "https://webpay3gint.transbank.cl/webpayserver/initTransaction"

async def _process_payment_callback(
    request: Request,
    token_ws: str | None,
    db: Session,
):
    form = await request.form() if request.method == "POST" else {}
    callback_data = {**dict(request.query_params), **dict(form)}
    if not token_ws:
        token_ws = callback_data.get("token_ws")
    if not token_ws:
        aborted_buy_order = callback_data.get("TBK_ORDEN_COMPRA")
        if aborted_buy_order:
            payment = db.query(Payment).filter(Payment.buy_order == aborted_buy_order).first()
            if payment:
                payment.status = PaymentStatus.failed
                db.commit()
                return RedirectResponse(
                    _frontend_payment_result(payment.freight_id, "cancelled"),
                    status_code=303,
                )
    if not token_ws:
        raise HTTPException(status_code=400, detail="Token requerido")
    payment = db.query(Payment).filter(Payment.webpay_token == token_ws).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Pago no encontrado")

    if payment.status == PaymentStatus.authorized:
        payout = ensure_driver_payout(db, payment)
        if payout:
            db.commit()
        return RedirectResponse(
            _frontend_payment_result(payment.freight_id, "success"),
            status_code=303,
        )

    status_before = payment.status.value if hasattr(payment.status, "value") else str(payment.status)
    if token_ws.startswith("SANDBOX_TOKEN_"):
        if not settings.ALLOW_SIMULATED_PAYMENTS:
            raise HTTPException(status_code=403, detail="Pagos simulados deshabilitados")
        commit = {
            "status": "AUTHORIZED",
            "response_code": 0,
            "buy_order": payment.buy_order,
            "amount": payment.amount,
            "authorization_code": f"SIM-{uuid.uuid4().hex[:6].upper()}",
            "transaction_id": None,
        }
    else:
        tbk_commit = commit_webpay_transaction(token_ws)
        commit = {
            "status": tbk_commit.status,
            "response_code": tbk_commit.response_code,
            "buy_order": tbk_commit.buy_order,
            "amount": tbk_commit.amount,
            "authorization_code": tbk_commit.authorization_code,
            "transaction_id": tbk_commit.transaction_id,
            "raw": tbk_commit.raw,
        }

    try:
        response_code = int(commit["response_code"])
    except (TypeError, ValueError):
        response_code = None
    transbank_status = str(commit["status"] or "").upper()
    authorized = (
        transbank_status == "AUTHORIZED"
        and response_code == 0
        and commit["buy_order"] == payment.buy_order
        and int(float(commit["amount"] or 0)) == int(payment.amount)
    )
    payment.status = PaymentStatus.authorized if authorized else PaymentStatus.failed
    if authorized:
        payment.paid_at = datetime.now(timezone.utc)
        payment.authorization_code = commit["authorization_code"]
        payment.transaction_id = commit["transaction_id"]
        payout = ensure_driver_payout(db, payment)
        if payout:
            record_audit_event(
                db,
                entity_type="driver_payout",
                entity_id=payout.id,
                event_type="driver_payout.created",
                after_data={
                    "payment_id": payment.id,
                    "freight_id": payout.freight_id,
                    "driver_id": payout.driver_id,
                    "amount": payout.amount,
                    "status": payout.status.value,
                },
                request=request,
            )
    record_audit_event(
        db,
        entity_type="payment",
        entity_id=payment.id,
        event_type="payment.authorized" if authorized else "payment.failed",
        before_data={"status": status_before},
        after_data={
            "status": payment.status.value,
            "paid_at": payment.paid_at.isoformat() if payment.paid_at else None,
            "authorization_code": payment.authorization_code,
            "buy_order": payment.buy_order,
            "transbank_status": transbank_status,
            "transbank_response_code": response_code,
        },
        request=request,
    )
    db.commit()
    if not authorized:
        return RedirectResponse(
            _frontend_payment_result(payment.freight_id, "failed"),
            status_code=303,
        )
    return RedirectResponse(
        _frontend_payment_result(payment.freight_id, "success"),
        status_code=303,
    )


@router.get("/callback", operation_id="payment_callback_get")
async def payment_callback_get(
    request: Request,
    token_ws: str | None = None,
    db: Session = Depends(get_db),
):
    return await _process_payment_callback(request, token_ws, db)


@router.post("/callback", operation_id="payment_callback_post")
async def payment_callback_post(
    request: Request,
    token_ws: str | None = None,
    db: Session = Depends(get_db),
):
    return await _process_payment_callback(request, token_ws, db)


@router.get("/{payment_id}", response_model=PaymentResponse)
def get_payment(
    payment_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    payment = (
        db.query(Payment)
        .join(FreightRequest, Payment.freight_id == FreightRequest.id)
        .filter(Payment.id == payment_id)
        .first()
    )
    if not payment:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    if current_user.role != UserRole.admin and payment.freight.client_id != current_user.id:
        raise HTTPException(status_code=403, detail="No tienes permiso para ver este pago")
    return payment
