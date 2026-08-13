import asyncio
from datetime import datetime, timezone
import logging
from urllib.parse import quote

import httpx

from app.core.config import settings


logger = logging.getLogger(__name__)
GOOGLE_MAPS_KEY = settings.GOOGLE_MAPS_KEY


class RouteCalculationError(RuntimeError):
    """A real road route could not be obtained from the configured provider."""


def _duration_seconds(value: str | int | float | None) -> float | None:
    if isinstance(value, str) and value.endswith("s"):
        try:
            return float(value[:-1])
        except ValueError:
            return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


async def _request_with_retries(
    client: httpx.AsyncClient,
    method: str,
    url: str,
    **kwargs,
) -> httpx.Response:
    attempts = settings.PRICING_ROUTE_MAX_RETRIES + 1
    last_error: Exception | None = None
    for attempt in range(attempts):
        try:
            response = await client.request(method, url, **kwargs)
            if response.status_code < 500 and response.status_code != 429:
                return response
            last_error = httpx.HTTPStatusError(
                "Transient route provider response",
                request=response.request,
                response=response,
            )
        except httpx.HTTPError as exc:
            last_error = exc
        if attempt < attempts - 1:
            await asyncio.sleep(0.15 * (2**attempt))
    raise RouteCalculationError("route_provider_unavailable") from last_error


async def _routes_api_route(
    client: httpx.AsyncClient,
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
) -> dict | None:
    response = await _request_with_retries(
        client,
        "POST",
        "https://routes.googleapis.com/directions/v2:computeRoutes",
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": GOOGLE_MAPS_KEY,
            "X-Goog-FieldMask": "routes.distanceMeters,routes.duration",
        },
        json={
            "origin": {
                "location": {
                    "latLng": {"latitude": origin_lat, "longitude": origin_lng}
                }
            },
            "destination": {
                "location": {
                    "latLng": {"latitude": dest_lat, "longitude": dest_lng}
                }
            },
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE",
        },
    )
    if response.status_code != 200:
        logger.info("Google Routes unavailable with status=%s", response.status_code)
        return None
    routes = response.json().get("routes") or []
    if not routes:
        return None
    route = routes[0]
    meters = route.get("distanceMeters")
    seconds = _duration_seconds(route.get("duration"))
    if not isinstance(meters, (int, float)) or not seconds or meters <= 0:
        return None
    return {
        "distance_km": float(meters) / 1000,
        "duration_minutes": max(round(seconds / 60, 1), 1),
        "distance_text": f"{float(meters) / 1000:.1f} km",
        "duration_text": f"{round(seconds / 60):.0f} min",
        "provider": "google_routes",
        "calculated_at": datetime.now(timezone.utc),
    }


async def _distance_matrix_route(
    client: httpx.AsyncClient,
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
) -> dict | None:
    response = await _request_with_retries(
        client,
        "GET",
        "https://maps.googleapis.com/maps/api/distancematrix/json",
        params={
            "origins": f"{origin_lat},{origin_lng}",
            "destinations": f"{dest_lat},{dest_lng}",
            "key": GOOGLE_MAPS_KEY,
            "units": "metric",
            "language": "es",
        },
    )
    if response.status_code != 200:
        logger.info("Google Distance Matrix unavailable with status=%s", response.status_code)
        return None
    try:
        element = response.json()["rows"][0]["elements"][0]
        if element["status"] != "OK":
            return None
        return {
            "distance_km": element["distance"]["value"] / 1000,
            "duration_minutes": max(round(element["duration"]["value"] / 60, 1), 1),
            "distance_text": element["distance"]["text"],
            "duration_text": element["duration"]["text"],
            "provider": "google_distance_matrix",
            "calculated_at": datetime.now(timezone.utc),
        }
    except (KeyError, IndexError, TypeError):
        return None


async def get_distance_and_duration(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
) -> dict:
    """Return a road route; geometric fallbacks are never used for billing."""
    if not GOOGLE_MAPS_KEY:
        logger.warning("Route calculation requested without a Google Maps key")
        raise RouteCalculationError("route_provider_not_configured")
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            route = await _routes_api_route(
                client, origin_lat, origin_lng, dest_lat, dest_lng
            )
            if route:
                return route
            route = await _distance_matrix_route(
                client, origin_lat, origin_lng, dest_lat, dest_lng
            )
            if route:
                return route
    except RouteCalculationError:
        logger.warning("Route provider did not recover after retries")
        raise
    except httpx.HTTPError as exc:
        logger.warning("Route provider request failed: %s", type(exc).__name__)
    raise RouteCalculationError("route_not_available")


async def geocode_address(address: str) -> dict | None:
    """Convert a Chilean address into coordinates for legacy callers."""
    url = "https://maps.googleapis.com/maps/api/geocode/json"
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(
            url,
            params={
                "address": address + ", Chile",
                "key": GOOGLE_MAPS_KEY,
                "language": "es",
            },
        )
        data = response.json()
    if data.get("results"):
        location = data["results"][0]["geometry"]["location"]
        return {
            "lat": location["lat"],
            "lng": location["lng"],
            "formatted": data["results"][0]["formatted_address"],
        }
    return None


def _autocomplete_suggestions(data: dict) -> list[dict]:
    """Keep the mobile API independent from the Google Places response shape."""
    suggestions: list[dict] = []
    for item in data.get("suggestions", [])[:5]:
        prediction = item.get("placePrediction") or {}
        place_id = prediction.get("placeId") or prediction.get("place", "").removeprefix("places/")
        text = (prediction.get("text") or {}).get("text", "").strip()
        structured = prediction.get("structuredFormat") or {}
        primary = (structured.get("mainText") or {}).get("text", "").strip()
        secondary = (structured.get("secondaryText") or {}).get("text", "").strip()
        if not place_id or not text:
            continue
        suggestions.append(
            {
                "place_id": place_id,
                "label": primary or text,
                "address": secondary or text,
                "full_address": text,
            }
        )
    return suggestions


async def autocomplete_chilean_addresses(
    query: str,
    *,
    session_token: str | None = None,
    latitude: float | None = None,
    longitude: float | None = None,
) -> list[dict]:
    """Return address predictions while keeping the Maps key on the server."""
    if not settings.GOOGLE_MAPS_KEY:
        return []
    payload: dict = {
        "input": query,
        "languageCode": "es",
        "regionCode": "CL",
        "includedRegionCodes": ["cl"],
    }
    if session_token:
        payload["sessionToken"] = session_token
    if latitude is not None and longitude is not None:
        payload["locationBias"] = {
            "circle": {
                "center": {"latitude": latitude, "longitude": longitude},
                "radius": 50000.0,
            }
        }
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": settings.GOOGLE_MAPS_KEY,
        "X-Goog-FieldMask": (
            "suggestions.placePrediction.placeId,"
            "suggestions.placePrediction.place,"
            "suggestions.placePrediction.text.text,"
            "suggestions.placePrediction.structuredFormat.mainText.text,"
            "suggestions.placePrediction.structuredFormat.secondaryText.text"
        ),
    }
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(
                "https://places.googleapis.com/v1/places:autocomplete",
                json=payload,
                headers=headers,
            )
            response.raise_for_status()
    except httpx.HTTPStatusError as exc:
        logger.warning("Google Places autocomplete failed with status %s", exc.response.status_code)
        return []
    except httpx.HTTPError as exc:
        logger.warning("Google Places autocomplete request failed: %s", type(exc).__name__)
        return []
    return _autocomplete_suggestions(response.json())


async def get_place_address(
    place_id: str,
    *,
    session_token: str | None = None,
) -> dict | None:
    """Resolve a prediction to the address and coordinates needed by a freight."""
    if not settings.GOOGLE_MAPS_KEY or not place_id:
        return None
    headers = {
        "X-Goog-Api-Key": settings.GOOGLE_MAPS_KEY,
        "X-Goog-FieldMask": "formattedAddress,location,displayName",
    }
    params = {"sessionToken": session_token} if session_token else None
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                "https://places.googleapis.com/v1/places/"
                f"{quote(place_id, safe='')}",
                headers=headers,
                params=params,
            )
            response.raise_for_status()
    except httpx.HTTPStatusError as exc:
        logger.warning("Google Place Details failed with status %s", exc.response.status_code)
        return None
    except httpx.HTTPError as exc:
        logger.warning("Google Place Details request failed: %s", type(exc).__name__)
        return None
    data = response.json()
    location = data.get("location") or {}
    latitude = location.get("latitude")
    longitude = location.get("longitude")
    if latitude is None or longitude is None:
        return None
    display_name = (data.get("displayName") or {}).get("text", "").strip()
    return {
        "address": data.get("formattedAddress") or display_name,
        "lat": float(latitude),
        "lng": float(longitude),
    }
