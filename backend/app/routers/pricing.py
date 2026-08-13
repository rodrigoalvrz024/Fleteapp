from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.core.rate_limit import check_rate_limit
from app.core.security import require_role
from app.database import get_db
from app.models.user import User
from app.schemas.freight import PricingEstimateRequest
from app.services.maps_service import RouteCalculationError
from app.services.pricing_estimate_service import calculate_pricing_estimate
from app.services.pricing_quote_service import create_pricing_quote
from app.services.pricing_service import PricingInputError


router = APIRouter(prefix="/pricing", tags=["Precios"])


@router.post("/estimate")
async def estimate_pricing(
    data: PricingEstimateRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("client")),
):
    """Create a short-lived automatic quote from route and cargo information."""
    check_rate_limit(
        request,
        scope="pricing-estimate",
        identifier=str(current_user.id),
        max_attempts=30,
        window_seconds=60 * 60,
    )
    try:
        route, pricing = await calculate_pricing_estimate(
            data,
            request_id=getattr(request.state, "request_id", None),
        )
    except RouteCalculationError:
        raise HTTPException(
            status_code=503,
            detail="No pudimos calcular la tarifa en este momento. Intenta nuevamente.",
        )
    except PricingInputError as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    response = {
        **pricing,
        "distance_km": round(route["distance_km"], 2),
        "duration_minutes": route["duration_minutes"],
        "distance_text": route.get("distance_text"),
        "duration_text": route.get("duration_text"),
        "route_provider": route.get("provider"),
        "route_calculated_at": route.get("calculated_at"),
        "quote_id": None,
        "expires_at": None,
    }
    if pricing.get("requires_manual_quote"):
        return response

    quote = create_pricing_quote(
        db,
        client_id=current_user.id,
        data=data,
        route=route,
        pricing=pricing,
    )
    db.commit()
    response["quote_id"] = quote.id
    response["expires_at"] = quote.expires_at
    return response
