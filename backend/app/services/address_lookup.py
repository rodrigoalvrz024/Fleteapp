import logging

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class AddressLookupUnavailable(Exception):
    pass


async def reverse_address(latitude: float, longitude: float) -> dict | None:
    """Suggest a street address; never replace the customer's selected point."""
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                "https://maps.googleapis.com/maps/api/geocode/json",
                params={"latlng": f"{latitude},{longitude}",
                        "key": settings.GOOGLE_MAPS_KEY, "language": "es"},
            )
            response.raise_for_status()
            data = response.json()
        if not isinstance(data, dict):
            raise ValueError("Invalid geocoder response")
        if data.get("status") == "ZERO_RESULTS":
            return None
        if data.get("status") != "OK":
            raise ValueError("Geocoder unavailable")
        results = data.get("results")
        if not isinstance(results, list):
            raise ValueError("Invalid geocoder results")
        # Locality/country/plus-code matches alone are not a pickup address.
        for kind in ("street_address", "premise", "subpremise", "route"):
            for item in results:
                if not isinstance(item, dict) or kind not in (item.get("types") or []):
                    continue
                address = item.get("formatted_address")
                if not isinstance(address, str):
                    continue
                address = address.strip()
                if 3 <= len(address) <= 250 and not any(ord(c) < 32 for c in address):
                    return {"address": address, "lat": latitude, "lng": longitude}
        return None
    except (httpx.HTTPError, ValueError, TypeError):
        # Provider URLs/errors can contain both the key and precise coordinates.
        logger.warning("Address lookup provider unavailable")
        raise AddressLookupUnavailable() from None
