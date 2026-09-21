from dataclasses import dataclass
import json
import logging
import re
from urllib.parse import urlsplit

import httpx
from fastapi import HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.core.config import settings


_HOSTS = {
    "integration": "https://webpay3gint.transbank.cl",
    "production": "https://webpay3g.transbank.cl",
}
_TRANSACTIONS_PATH = "/rswebpaytransaction/api/webpay/v1.2/transactions"
# Public integration credentials, not merchant secrets. Never used in production.
# https://www.transbankdevelopers.cl/referencia/webpay
_INTEGRATION_COMMERCE_CODE = "597055555532"
_INTEGRATION_API_KEY = "579B532A7440BB0C9079DED94D31EA1615BACEB56610332264630D42D0A36B1C"
_MAX_RESPONSE_BYTES = 64 * 1024


class _WebpayLogFilter(logging.Filter):
    def filter(self, record):
        if any(host in record.getMessage() for host in _HOSTS.values()):
            record.msg = "Webpay HTTP operation (payment details omitted)"
            record.args = ()
            record.exc_info = None
            record.exc_text = None
        return True


# HTTPX logs request URLs at INFO; commit URLs contain a bearer payment token.
logging.getLogger("httpx").addFilter(_WebpayLogFilter())


class _CreateRequest(BaseModel):
    model_config = ConfigDict(strict=True)
    buy_order: str = Field(min_length=1, max_length=26)
    session_id: str = Field(min_length=1, max_length=61)
    amount: int = Field(gt=0)
    return_url: str = Field(min_length=1, max_length=255)


class _CreateResponse(BaseModel):
    model_config = ConfigDict(strict=True)
    token: str = Field(pattern=r"^[A-Za-z0-9_-]{1,64}$")
    url: str = Field(min_length=1, max_length=2048)


class _CommitResponse(BaseModel):
    model_config = ConfigDict(strict=True, allow_inf_nan=False)
    status: str = Field(min_length=1, max_length=32)
    response_code: int
    buy_order: str = Field(min_length=1, max_length=26)
    amount: float = Field(ge=0, multiple_of=1)
    authorization_code: str | None = None
    accounting_date: str | None = None


class WebpayStatusResult(_CommitResponse):
    response_code: int | None = None
    session_id: str = Field(min_length=1, max_length=61)
    authorization_code: str | None = Field(default=None, max_length=6)
    accounting_date: str | None = Field(default=None, max_length=4)


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


def _configuration() -> tuple[str, dict[str, str]]:
    environment = settings.TRANSBANK_ENVIRONMENT.lower()
    if environment not in _HOSTS:
        raise HTTPException(status_code=503, detail="Entorno de Webpay no configurado")
    is_production = environment == "production"
    if is_production and (
        not settings.TRANSBANK_COMMERCE_CODE or not settings.TRANSBANK_API_KEY
    ):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Credenciales productivas de Transbank no configuradas",
        )

    return _HOSTS[environment], {
        "Tbk-Api-Key-Id": settings.TRANSBANK_COMMERCE_CODE or _INTEGRATION_COMMERCE_CODE,
        "Tbk-Api-Key-Secret": settings.TRANSBANK_API_KEY or _INTEGRATION_API_KEY,
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def _provider_error() -> HTTPException:
    return HTTPException(
        status_code=503,
        detail="No se pudo confirmar la operacion con Webpay. Revisa el estado del pago antes de reintentar.",
    )


def _request(method: str, suffix: str = "", payload: dict | None = None) -> dict:
    host, headers = _configuration()
    try:
        # No redirects or retries: a timeout can leave a payment outcome unknown.
        with httpx.Client(timeout=httpx.Timeout(30.0, connect=5.0),
                          follow_redirects=False, trust_env=False) as client:
            with client.stream(method, host + _TRANSACTIONS_PATH + suffix,
                               headers=headers, json=payload) as response:
                if not 200 <= response.status_code < 300:
                    raise _provider_error()
                content = bytearray()
                for chunk in response.iter_bytes(chunk_size=8192):
                    content.extend(chunk)
                    if len(content) > _MAX_RESPONSE_BYTES:
                        raise _provider_error()
        data = json.loads(content)
        if not isinstance(data, dict):
            raise _provider_error()
        return data
    except (httpx.HTTPError, ValueError):
        # Upstream errors can contain tokens, headers or raw response data.
        raise _provider_error() from None


def create_webpay_transaction(
    *,
    buy_order: str,
    session_id: str,
    amount: int,
    return_url: str,
) -> WebpayCreateResult:
    try:
        request = _CreateRequest(buy_order=buy_order, session_id=session_id,
                                 amount=amount, return_url=return_url)
        callback = urlsplit(return_url)
        if (callback.scheme not in {"http", "https"} or not callback.hostname
                or callback.username or callback.password or callback.fragment):
            raise ValueError("Invalid callback")
        if settings.TRANSBANK_ENVIRONMENT.lower() == "production" and callback.scheme != "https":
            raise ValueError("HTTPS required")
    except (ValidationError, ValueError):
        raise HTTPException(status_code=400, detail="Datos de pago invalidos") from None
    data = _request("POST", payload=request.model_dump())
    try:
        response = _CreateResponse.model_validate(data)
        redirect = urlsplit(response.url)
        expected_host = urlsplit(_HOSTS[settings.TRANSBANK_ENVIRONMENT.lower()]).netloc
        if (redirect.scheme != "https" or redirect.netloc != expected_host
                or redirect.username or redirect.password or redirect.fragment):
            raise ValueError("Unexpected payment destination")
    except (ValidationError, ValueError):
        raise _provider_error() from None
    return WebpayCreateResult(token=response.token, url=response.url)


def commit_webpay_transaction(token_ws: str) -> WebpayCommitResult:
    if not isinstance(token_ws, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", token_ws):
        raise HTTPException(status_code=400, detail="Token de pago invalido")
    data = _request("PUT", suffix=f"/{token_ws}")
    try:
        response = _CommitResponse.model_validate(data)
    except ValidationError:
        raise _provider_error() from None
    return WebpayCommitResult(
        status=response.status,
        response_code=response.response_code,
        buy_order=response.buy_order,
        amount=response.amount,
        authorization_code=response.authorization_code,
        transaction_id=response.accounting_date,
        raw=data,
    )


def get_webpay_transaction_status(token_ws: str) -> WebpayStatusResult:
    if not isinstance(token_ws, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", token_ws):
        raise HTTPException(status_code=400, detail="Token de pago invalido")
    data = _request("GET", suffix=f"/{token_ws}")
    try:
        return WebpayStatusResult.model_validate(data)
    except ValidationError:
        raise _provider_error() from None
