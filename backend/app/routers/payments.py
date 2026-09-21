import html
import re
import uuid
from decimal import Decimal, InvalidOperation
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool
from app.services.row_lock_service import lock_first
from datetime import datetime, timezone
from app.database import get_db
from app.models.user import User, UserRole
from app.models.freight import FreightRequest, FreightStatus
from app.models.payment import Payment, PaymentStatus, PaymentMethod
from app.schemas.payment import (
    PaymentCreate, PaymentResponse, WebpayInitResponse,
    PaymentReconcileRequest, PaymentReconcileResponse,
)
from app.core.rate_limit import check_rate_limit
from app.core.security import get_current_user, require_role
from app.core.config import settings
from app.services.audit_service import record_audit_event
from app.services.cloud_tasks_service import enqueue_freight_driver_notification_task
from app.services.freight_notification_service import notify_available_drivers
from app.services.payout_service import ensure_driver_payout
from app.services.pricing_history_service import record_pricing_snapshot
from app.services.transbank_service import (
    commit_webpay_transaction,
    create_webpay_transaction,
    get_webpay_transaction_status,
)
router = APIRouter(prefix="/payments", tags=["Pagos"])


def _frontend_payment_result(freight_id: int, result: str) -> str:
    return (
        f"{settings.FRONTEND_URL.rstrip('/')}/#/app/client/freights/"
        f"{freight_id}?payment={result}"
    )


def _clp_amount(value) -> int:
    try:
        amount = Decimal(str(value))
        if (not amount.is_finite() or amount <= 0
                or amount != amount.to_integral_value() or amount >= 10 ** 17):
            raise ValueError("Invalid CLP amount")
    except (InvalidOperation, ValueError, TypeError):
        raise HTTPException(status_code=409, detail="El monto del pago requiere revision") from None
    return int(amount)


def _checkout_response(token: str, base_url: str, webpay_url: str | None = None) -> WebpayInitResponse:
    simulated = token.startswith("SANDBOX_TOKEN_")
    url = webpay_url or payment_redirect_url()
    if simulated and webpay_url is None:
        url += f"?token_ws={token}"
    return WebpayInitResponse(
        token=token,
        url=url,
        redirect_url=(f"{base_url}/payments/callback?token_ws={token}"
                      if simulated else f"{base_url}/payments/webpay/{token}"),
    )


@router.post("/initiate", response_model=WebpayInitResponse)
def initiate_payment(
    data: PaymentCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client")),
):
    if (
        settings.ALLOW_SIMULATED_PAYMENTS
        and settings.TRANSBANK_ENVIRONMENT.lower() == "production"
    ):
        raise HTTPException(
            status_code=503,
            detail="La configuracion de pagos no esta disponible.",
        )
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
    freight = lock_first(db.query(FreightRequest).filter(
        FreightRequest.id == data.freight_id,
        FreightRequest.client_id == current_user.id,
        FreightRequest.status != FreightStatus.cancelled,
    ))
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no disponible para pago")

    # Lock the freight even when no payment exists, then its payment. Callbacks
    # and completion use the same order so they cannot replace each other's state.
    payment = lock_first(db.query(Payment).filter(Payment.freight_id == freight.id))
    if payment and payment.status == PaymentStatus.authorized:
        raise HTTPException(status_code=400, detail="Este flete ya fue pagado")
    if payment and payment.status == PaymentStatus.refunded:
        raise HTTPException(status_code=409, detail="Este pago fue reembolsado y no puede reiniciarse")

    amount = _clp_amount(freight.final_price if freight.final_price is not None else freight.estimated_price)
    base_url = (
        settings.PUBLIC_API_URL.rstrip("/")
        if settings.PUBLIC_API_URL
        else str(request.base_url).rstrip("/")
    )
    if payment and payment.status == PaymentStatus.pending and (payment.webpay_token or payment.buy_order):
        token = payment.webpay_token
        if (payment.method != PaymentMethod.webpay or not payment.buy_order
                or not token or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", token)
                or _clp_amount(payment.amount) != amount
                or (token.startswith("SANDBOX_TOKEN_") and not settings.ALLOW_SIMULATED_PAYMENTS)):
            raise HTTPException(status_code=409, detail="El pago pendiente requiere revision antes de reintentar")
        return _checkout_response(token, base_url)

    buy_order = f"FLETE-{freight.id}-{uuid.uuid4().hex[:8].upper()}"
    # Simulation and the Webpay REST integration share the same payment record.
    if payment is None:
        payment = Payment(freight_id=freight.id)
        db.add(payment)
    payment.amount = amount
    payment.method = data.method
    payment.buy_order = buy_order
    payment.status = PaymentStatus.pending
    payment.webpay_token = None
    payment.authorization_code = None
    payment.transaction_id = None
    payment.paid_at = None
    payment.last_modified_by = current_user.id
    db.flush()

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

    return _checkout_response(payment.webpay_token, base_url, webpay_url)


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
    background_tasks: BackgroundTasks,
):
    form = await request.form() if request.method == "POST" else None
    callback_data = {}
    for key, maximum in (("token_ws", 64), ("TBK_TOKEN", 64),
                         ("TBK_ORDEN_COMPRA", 26), ("TBK_ID_SESION", 61)):
        values = request.query_params.getlist(key) + (form.getlist(key) if form is not None else [])
        if len(values) > 1 or (values and (not isinstance(values[0], str) or len(values[0]) > maximum)):
            raise HTTPException(status_code=400, detail="Retorno de pago invalido")
        callback_data[key] = values[0] if values else None

    return await run_in_threadpool(_apply_payment_callback, request, callback_data, db, background_tasks)


def _apply_payment_callback(request, callback_data, db, background_tasks):
    try:
        return _apply_payment_callback_locked(request, callback_data, db, background_tasks)
    finally:
        # Release locks on early returns/errors before the worker is released.
        db.rollback()


def _apply_payment_callback_locked(request, callback_data, db, background_tasks):
    token_ws = callback_data["token_ws"]
    aborted_token = callback_data["TBK_TOKEN"]
    aborted_order = callback_data["TBK_ORDEN_COMPRA"]
    for value in (token_ws, aborted_token):
        if value and not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value):
            raise HTTPException(status_code=400, detail="Retorno de pago invalido")
    if token_ws and aborted_token and token_ws != aborted_token:
        raise HTTPException(status_code=400, detail="Retorno de pago invalido")

    # Tokenless timeout fields come from the browser, not authenticated Webpay.
    # Do not look up or change a payment based on a public order/session ID.
    if not token_ws and not aborted_token:
        if aborted_order and callback_data["TBK_ID_SESION"]:
            return RedirectResponse(
                f"{settings.FRONTEND_URL.rstrip('/')}/#/app/client/freights?payment=unconfirmed",
                status_code=303,
            )
        raise HTTPException(status_code=400, detail="Token requerido")

    if aborted_token and not aborted_order:
        raise HTTPException(status_code=400, detail="Retorno de pago invalido")
    query = db.query(Payment).filter(Payment.webpay_token == (aborted_token or token_ws))
    if aborted_token:
        query = query.filter(Payment.buy_order == aborted_order)
    freight_id = query.with_entities(Payment.freight_id).scalar()
    if freight_id is None:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    # Match initiation/completion lock order; recheck the token after waiting.
    freight = lock_first(db.query(FreightRequest).filter(FreightRequest.id == freight_id))
    if not freight:
        raise HTTPException(status_code=404, detail="Flete no encontrado")
    payment = lock_first(query)
    if not payment:
        raise HTTPException(status_code=404, detail="Pago no encontrado")

    if payment.status != PaymentStatus.pending:
        return RedirectResponse(
            _frontend_payment_result(
                payment.freight_id, "success" if payment.status == PaymentStatus.authorized else "failed"
            ),
            status_code=303,
        )

    if aborted_token:
        # Even a matching bearer token is not proof of a bank-side outcome.
        # Keep pending until provider confirmation/reconciliation, including
        # Webpay's error return containing BOTH token_ws and TBK_TOKEN.
        result = "unconfirmed" if token_ws else "cancelled"
        record_audit_event(
            db,
            entity_type="payment",
            entity_id=payment.id,
            event_type="payment.checkout_error" if token_ws else "payment.checkout_aborted",
            before_data={"status": payment.status.value},
            after_data={"status": payment.status.value, "financial_state_changed": False},
            request=request,
        )
        db.commit()
        return RedirectResponse(_frontend_payment_result(payment.freight_id, result), status_code=303)

    if token_ws.startswith("SANDBOX_TOKEN_"):
        if (not settings.ALLOW_SIMULATED_PAYMENTS
                or settings.TRANSBANK_ENVIRONMENT.lower() == "production"):
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

    authorized = _apply_verified_payment_outcome(db, payment, commit, request, background_tasks)
    return RedirectResponse(
        _frontend_payment_result(payment.freight_id, "success" if authorized else "failed"),
        status_code=303,
    )


def _apply_verified_payment_outcome(db, payment, commit, request, background_tasks):
    status_before = payment.status.value
    try:
        response_code = int(commit["response_code"])
    except (TypeError, ValueError):
        response_code = None
    transbank_status = str(commit["status"] or "").upper()
    try:
        matching_amount = _clp_amount(commit["amount"]) == _clp_amount(payment.amount)
    except HTTPException:
        matching_amount = False
    authorized = transbank_status == "AUTHORIZED" and response_code == 0 and bool((commit["authorization_code"] or "").strip())
    declined = transbank_status == "FAILED" and response_code is not None and response_code < 0
    if (commit["buy_order"] != payment.buy_order or not matching_amount
            or not (authorized or declined)):
        # An inconsistent response is not proof of failure: retain the checkout
        # for reconciliation rather than permit a replacement charge.
        raise HTTPException(status_code=503, detail="El pago requiere verificacion antes de reintentar")
    payment.status = PaymentStatus.authorized if authorized else PaymentStatus.failed
    notification = None
    if authorized:
        payment.paid_at = datetime.now(timezone.utc)
        payment.authorization_code = commit["authorization_code"]
        payment.transaction_id = commit["transaction_id"]
        if payment.freight:
            record_pricing_snapshot(
                db,
                payment.freight,
                snapshot_type="payment_authorized",
                final_customer_price=float(payment.amount),
                captured_at=payment.paid_at,
            )
        freight = payment.freight
        if freight and freight.status == FreightStatus.completed:
            payout = ensure_driver_payout(db, payment)
            if payout:
                record_audit_event(
                    db,
                    entity_type="driver_payout",
                    entity_id=payout.id,
                    event_type="driver_payout.created",
                    after_data={
                        "payment_id": payout.payment_id,
                        "freight_id": payout.freight_id,
                        "driver_id": payout.driver_id,
                        "amount": payout.amount,
                        "status": payout.status.value,
                    },
                    request=request,
                )
        if (
            freight
            and freight.status == FreightStatus.pending
            and freight.driver_id is None
            and settings.firebase_push_configured
        ):
            notification = {
                "freight_id": freight.id,
                "title": "Nuevo flete disponible",
                "body": (
                    f"{'URGENTE' if freight.is_urgent else 'Programado'} - "
                    f"${payment.amount:,.0f} CLP"
                ),
                "data": {
                    "freight_id": str(freight.id),
                    "type": "new_freight",
                    "mode": freight.mode.value
                    if hasattr(freight.mode, "value")
                    else str(freight.mode),
                    "route": f"/app/driver/freights/{freight.id}",
                },
            }
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
    if notification:
        if settings.NOTIFICATION_TASKS_ENABLED:
            background_tasks.add_task(
                enqueue_freight_driver_notification_task,
                **notification,
            )
        else:
            background_tasks.add_task(notify_available_drivers, **notification)
    return authorized


@router.post("/{payment_id}/reconcile", response_model=PaymentReconcileResponse)
def reconcile_payment(
    payment_id: int,
    data: PaymentReconcileRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client", "admin")),
):
    check_rate_limit(request, scope="payment-reconcile-user", identifier=str(current_user.id),
                     max_attempts=20, window_seconds=15 * 60)
    query = (db.query(Payment.freight_id).join(FreightRequest, Payment.freight_id == FreightRequest.id)
             .filter(Payment.id == payment_id))
    if current_user.role != UserRole.admin:
        query = query.filter(FreightRequest.client_id == current_user.id)
    freight_id = query.scalar()
    if freight_id is None:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    check_rate_limit(request, scope="payment-reconcile", identifier=str(payment_id),
                     max_attempts=6, window_seconds=15 * 60)
    try:
        freight = lock_first(db.query(FreightRequest).filter(FreightRequest.id == freight_id))
        if not freight or (current_user.role != UserRole.admin and freight.client_id != current_user.id):
            raise HTTPException(status_code=404, detail="Pago no encontrado")
        payment = lock_first(db.query(Payment).filter(Payment.id == payment_id, Payment.freight_id == freight_id))
        if not payment:
            raise HTTPException(status_code=404, detail="Pago no encontrado")
        if payment.status != PaymentStatus.pending:
            return PaymentReconcileResponse(payment_id=payment.id, freight_id=freight.id,
                                            status=payment.status, result="unchanged")
        if (payment.method != PaymentMethod.webpay or not payment.buy_order or not payment.webpay_token
                or payment.webpay_token.startswith("SANDBOX_TOKEN_")):
            raise HTTPException(status_code=409, detail="Este pago requiere revision manual")
        outcome = get_webpay_transaction_status(payment.webpay_token)
        try:
            matching_amount = _clp_amount(outcome.amount) == _clp_amount(payment.amount)
        except HTTPException:
            matching_amount = False
        if (outcome.buy_order != payment.buy_order
                or outcome.session_id != f"user-{freight.client_id}"
                or not matching_amount):
            raise HTTPException(status_code=503, detail="No se pudo verificar la identidad del pago")
        authorized = outcome.status == "AUTHORIZED" and outcome.response_code == 0 and bool((outcome.authorization_code or "").strip())
        declined = outcome.status == "FAILED" and outcome.response_code is not None and outcome.response_code < 0
        result = "resolved" if authorized or declined else (
            "pending" if outcome.status == "INITIALIZED" else "review_required"
        )
        if authorized and freight.status == FreightStatus.cancelled:
            result = "review_required"
        record_audit_event(
            db, actor=current_user, entity_type="payment", entity_id=payment.id,
            event_type="payment.reconciled", before_data={"status": payment.status.value},
            after_data={"result": result, "provider_confirmed": bool(authorized or declined)},
            request=request,
        )
        if authorized or declined:
            _apply_verified_payment_outcome(db, payment, {
                "status": outcome.status, "response_code": outcome.response_code,
                "buy_order": outcome.buy_order, "amount": outcome.amount,
                "authorization_code": outcome.authorization_code, "transaction_id": outcome.accounting_date,
            }, request, background_tasks)
        else:
            db.commit()
        return PaymentReconcileResponse(payment_id=payment.id, freight_id=freight.id,
                                        status=payment.status, result=result)
    finally:
        db.rollback()


@router.get("/callback", operation_id="payment_callback_get")
async def payment_callback_get(
    request: Request,
    background_tasks: BackgroundTasks,
    token_ws: str | None = None,
    db: Session = Depends(get_db),
):
    return await _process_payment_callback(request, token_ws, db, background_tasks)


@router.post("/callback", operation_id="payment_callback_post")
async def payment_callback_post(
    request: Request,
    background_tasks: BackgroundTasks,
    token_ws: str | None = None,
    db: Session = Depends(get_db),
):
    return await _process_payment_callback(request, token_ws, db, background_tasks)


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
