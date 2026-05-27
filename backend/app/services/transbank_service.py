from dataclasses import dataclass

from fastapi import HTTPException, status

from app.core.config import settings


@dataclass
class WebpayCreateResult:
    token: str
    url: str


@dataclass
class WebpayCommitResult:
    status: str
    response_code: int | None
    buy_order: str | None
    amount: float | None
    authorization_code: str | None
    transaction_id: str | None
    raw: dict


def _transaction():
    try:
        from transbank.common.integration_type import IntegrationType
        from transbank.common.options import WebpayOptions
        from transbank.webpay.webpay_plus.transaction import Transaction
    except ImportError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="SDK de Transbank no disponible",
        ) from exc

    if not settings.TRANSBANK_COMMERCE_CODE or not settings.TRANSBANK_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Credenciales de Transbank no configuradas",
        )

    environment = (
        IntegrationType.LIVE
        if settings.TRANSBANK_ENVIRONMENT.lower() == "production"
        else IntegrationType.TEST
    )
    return Transaction(
        WebpayOptions(
            settings.TRANSBANK_COMMERCE_CODE,
            settings.TRANSBANK_API_KEY,
            environment,
        )
    )


def create_webpay_transaction(
    *,
    buy_order: str,
    session_id: str,
    amount: int,
    return_url: str,
) -> WebpayCreateResult:
    response = _transaction().create(buy_order, session_id, amount, return_url)
    return WebpayCreateResult(token=response["token"], url=response["url"])


def commit_webpay_transaction(token_ws: str) -> WebpayCommitResult:
    response = _transaction().commit(token_ws)
    return WebpayCommitResult(
        status=str(response.get("status", "")),
        response_code=response.get("response_code"),
        buy_order=response.get("buy_order"),
        amount=response.get("amount"),
        authorization_code=response.get("authorization_code"),
        transaction_id=response.get("accounting_date"),
        raw=response,
    )
