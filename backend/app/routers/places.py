from fastapi import APIRouter, Depends, HTTPException, Query, Request

from app.core.config import settings
from app.core.rate_limit import check_rate_limit
from app.core.security import get_current_user
from app.models.user import User
from app.services.maps_service import autocomplete_chilean_addresses, get_place_address

router = APIRouter(prefix="/places", tags=["Direcciones"])


def _require_places_configuration() -> None:
    if not settings.GOOGLE_MAPS_KEY:
        raise HTTPException(
            status_code=503,
            detail="Las sugerencias de direcciones aun no estan configuradas.",
        )


@router.get("/autocomplete")
async def autocomplete_addresses(
    request: Request,
    q: str = Query(min_length=3, max_length=160),
    session_token: str | None = Query(default=None, min_length=16, max_length=128),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
    current_user: User = Depends(get_current_user),
):
    _require_places_configuration()
    check_rate_limit(
        request,
        scope="places-autocomplete-user",
        identifier=str(current_user.id),
        max_attempts=30,
        window_seconds=60,
    )
    suggestions = await autocomplete_chilean_addresses(
        q.strip(),
        session_token=session_token,
        latitude=lat,
        longitude=lng,
    )
    return {"suggestions": suggestions}


@router.get("/{place_id}")
async def get_address_details(
    place_id: str,
    request: Request,
    session_token: str | None = Query(default=None, min_length=16, max_length=128),
    current_user: User = Depends(get_current_user),
):
    _require_places_configuration()
    check_rate_limit(
        request,
        scope="places-details-user",
        identifier=str(current_user.id),
        max_attempts=12,
        window_seconds=60,
    )
    place = await get_place_address(place_id, session_token=session_token)
    if not place:
        raise HTTPException(status_code=404, detail="No encontramos esa direccion.")
    return place
