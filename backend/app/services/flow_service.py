import hashlib
import hmac
import httpx
from datetime import datetime
from app.core.config import settings

FLOW_API_URL_SANDBOX    = "https://sandbox.flow.cl/api"
FLOW_API_URL_PRODUCTION = "https://www.flow.cl/api"

def get_flow_url() -> str:
    if settings.FLOW_ENVIRONMENT == "sandbox":
        return FLOW_API_URL_SANDBOX
    return FLOW_API_URL_PRODUCTION

def sign_params(params: dict) -> str:
    keys = sorted(params.keys())
    to_sign = ""
    for key in keys:
        to_sign += f"{key}{params[key]}"
    return hmac.new(
        settings.FLOW_SECRET_KEY.encode(),
        to_sign.encode(),
        hashlib.sha256
    ).hexdigest()

async def create_payment(
    freight_id: int,
    amount: int,
    email: str,
    concept: str,
    callback_url: str,
    return_url: str,
) -> dict:
    commerce_order = f"FLETE-{freight_id}-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    params = {
        "apiKey":          settings.FLOW_API_KEY,
        "commerceOrder":   commerce_order,
        "subject":         concept,
        "currency":        "CLP",
        "amount":          str(amount),
        "email":           email,
        "urlConfirmation": callback_url,
        "urlReturn":       return_url,
    }
    params["s"] = sign_params(params)
    async with httpx.AsyncClient() as client:
        response = await client.post(f"{get_flow_url()}/payment/create", data=params)
    data = response.json()
    if "url" not in data or "token" not in data:
        raise Exception(f"Error Flow: {data}")
    return {
        "flow_token":     data["token"],
        "payment_url":   f"{data['url']}?token={data['token']}",
        "commerce_order": commerce_order,
    }

async def get_payment_status(flow_token: str) -> dict:
    params = {"apiKey": settings.FLOW_API_KEY, "token": flow_token}
    params["s"] = sign_params(params)
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{get_flow_url()}/payment/getStatus", params=params)
    return response.json()

async def refund_payment(commerce_order: str, amount: int) -> dict:
    params = {
        "apiKey":              settings.FLOW_API_KEY,
        "refundCommerceOrder": f"REFUND-{commerce_order}",
        "receiverEmail":       "",
        "amount":              str(amount),
        "commerceTrxId":       commerce_order,
    }
    params["s"] = sign_params(params)
    async with httpx.AsyncClient() as client:
        response = await client.post(f"{get_flow_url()}/refund/create", data=params)
    return response.json()
