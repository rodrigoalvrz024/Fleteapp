import httpx
import math
from app.core.config import settings

GOOGLE_MAPS_KEY = "AIzaSyBcwbVhe0iIpkjmPJS94kc6JhZP2v16TsY"  # o agrégala al .env

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