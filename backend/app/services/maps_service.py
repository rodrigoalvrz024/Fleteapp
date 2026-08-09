import httpx
import math
import os
from urllib.parse import quote
from app.core.config import settings

GOOGLE_MAPS_KEY = settings.GOOGLE_MAPS_KEY  # o agrégala al .env

async def get_distance_and_duration(
    origin_lat: float, origin_lng: float,
    dest_lat: float, dest_lng: float
) -> dict:
    """Llama a Google Distance Matrix API para distancia y tiempo real."""
    url = "https://maps.googleapis.com/maps/api/distancematrix/json"
    params = {
        "origins": f"{origin_lat},{origin_lng}",
        "destinations": f"{dest_lat},{dest_lng}",
        "key": GOOGLE_MAPS_KEY,
        "units": "metric",
        "language": "es",
    }
    async with httpx.AsyncClient() as client:
        res = await client.get(url, params=params)
        data = res.json()

    try:
        element = data["rows"][0]["elements"][0]
        if element["status"] == "OK":
            return {
                "distance_km": element["distance"]["value"] / 1000,
                "duration_minutes": element["duration"]["value"] // 60,
                "distance_text": element["distance"]["text"],
                "duration_text": element["duration"]["text"],
            }
    except Exception:
        pass

    # Fallback: fórmula Haversine si la API falla
    R = 6371
    phi1, phi2 = math.radians(origin_lat), math.radians(dest_lat)
    dphi = math.radians(dest_lat - origin_lat)
    dlambda = math.radians(dest_lng - origin_lng)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    dist = R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return {"distance_km": round(dist, 2), "duration_minutes": int(dist * 3), "distance_text": f"{dist:.1f} km", "duration_text": f"{int(dist*3)} min"}

async def geocode_address(address: str) -> dict | None:
    """Convierte dirección en coordenadas."""
    url = "https://maps.googleapis.com/maps/api/geocode/json"
    async with httpx.AsyncClient() as client:
        res = await client.get(url, params={"address": address + ", Chile", "key": GOOGLE_MAPS_KEY, "language": "es"})
        data = res.json()
    if data.get("results"):
        loc = data["results"][0]["geometry"]["location"]
        return {"lat": loc["lat"], "lng": loc["lng"], "formatted": data["results"][0]["formatted_address"]}
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
    except httpx.HTTPError:
        return []
    return _autocomplete_suggestions(response.json())


async def get_place_address(
    place_id: str,
    *,
    session_token: str | None = None,
) -> dict | None:
    """Resolve a selected prediction to the address and coordinates needed by a freight."""
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
    except httpx.HTTPError:
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
