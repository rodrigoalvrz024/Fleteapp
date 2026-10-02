import os
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("DATABASE_URL", "postgresql://localhost/synthetic")
os.environ.setdefault("SECRET_KEY", "synthetic-address-unit-test-not-a-real-secret")

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.routers import places
from app.schemas.freight import FreightCreate
from app.services import address_lookup


class LookupTests(unittest.IsolatedAsyncioTestCase):
    async def lookup(self, data, code=200):
        response = httpx.Response(code, json=data, request=httpx.Request("GET", "https://example.test"))
        client = AsyncMock()
        client.get.return_value = response
        with patch.object(address_lookup.httpx, "AsyncClient") as factory:
            factory.return_value.__aenter__.return_value = client
            result = await address_lookup.reverse_address(-33.45, -70.65)
        self.assertEqual(client.get.call_args.kwargs['params']['latlng'], '-33.45,-70.65')
        return result

    async def test_prefers_street_address_preserves_pin_not_geocoder_geometry(self):
        result = await self.lookup({"status": "OK", "results": [
            {"types": ["locality"], "formatted_address": "Santiago"},
            {"types": ["route"], "formatted_address": "Av. Providencia"},
            {"types": ["street_address"], "formatted_address": "Av. Providencia 1234, Providencia, Chile",
             "geometry": {"location": {"lat": 9, "lng": 8}}},
        ]})
        self.assertEqual(result, {"address": "Av. Providencia 1234, Providencia, Chile", "lat": -33.45, "lng": -70.65})

    async def test_does_not_invent_address_from_locality_plus_code_or_empty_results(self):
        for data in [{"status": "ZERO_RESULTS"}, {"status": "OK", "results": [
            {"types": ["locality"], "formatted_address": "Santiago"},
            {"types": ["plus_code"], "formatted_address": "ABCD+12"}]}]:
            self.assertIsNone(await self.lookup(data))

    async def test_malformed_errors_denial_quota_are_unavailable(self):
        for data in [[], {}, {"status": "REQUEST_DENIED", "error_message": "secret"},
                     {"status": "OVER_QUERY_LIMIT"}, {"status": "OK", "results": "bad"}]:
            with self.assertRaises(address_lookup.AddressLookupUnavailable):
                await self.lookup(data)
        with self.assertRaises(address_lookup.AddressLookupUnavailable):
            await self.lookup({}, code=500)

    async def test_network_errors_do_not_leak_key_or_coordinates(self):
        with patch.object(address_lookup.httpx, "AsyncClient") as factory:
            factory.return_value.__aenter__.side_effect = httpx.ConnectError('synthetic-secret-coordinates')
            with self.assertLogs(address_lookup.logger, level='WARNING') as logs:
                with self.assertRaises(address_lookup.AddressLookupUnavailable):
                    await address_lookup.reverse_address(-33.45, -70.65)
            self.assertNotIn('synthetic-secret', str(logs.output))


class EndpointTests(unittest.TestCase):
    def setUp(self):
        self.app = FastAPI()
        self.app.include_router(places.router)
        self.client = self.enterContext(TestClient(self.app))
        self.enterContext(patch.object(places.settings, 'GOOGLE_MAPS_KEY', 'synthetic-key'))
        self.rate = self.enterContext(patch.object(places, 'check_rate_limit'))
        self.lookup = self.enterContext(patch.object(places, 'reverse_address', new_callable=AsyncMock))
        self.lookup.return_value = {"address": "Calle Prueba 123, Santiago", "lat": -33.45, "lng": -70.65}

    def post(self, **changes):
        return self.client.post('/places/reverse-geocode', json={"lat": -33.45, "lng": -70.65, **changes})

    def authenticate(self, role='client'):
        self.app.dependency_overrides[places.get_current_user] = lambda: SimpleNamespace(id=7, role=role)

    def test_anonymous_denied(self):
        self.assertEqual(self.post().status_code, 401)
        self.lookup.assert_not_awaited()

    def test_authenticated_roles_are_rate_limited_and_receive_only_address_and_point(self):
        for role in ['client', 'driver', 'admin']:
            self.authenticate(role)
            response = self.post()
            self.assertEqual(response.status_code, 200)
            self.assertEqual(set(response.json()), {'address', 'lat', 'lng'})
            self.assertEqual(self.rate.call_args.kwargs['identifier'], '7')
        self.rate.side_effect = HTTPException(429, 'Too many requests')
        self.assertEqual(self.post().status_code, 429)

    def test_invalid_coordinates_and_extra_fields_rejected(self):
        self.authenticate()
        for changes in [dict(lat=91), dict(lng=-181), dict(lat='NaN'), dict(lng='inf'), dict(user_id=8)]:
            self.assertEqual(self.post(**changes).status_code, 422)
        self.lookup.assert_not_awaited()

    def test_configuration_missing_not_found_and_unavailable(self):
        self.authenticate()
        with patch.object(places.settings, 'GOOGLE_MAPS_KEY', ''):
            self.assertEqual(self.post().status_code, 503)
        self.lookup.return_value = None
        self.assertEqual(self.post().status_code, 404)
        self.lookup.side_effect = address_lookup.AddressLookupUnavailable('private error')
        response = self.post()
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private error', response.text)

    def test_new_freights_reject_placeholders_preserve_customer_address(self):
        base = dict(origin_address='Calle Prueba 123, Santiago', origin_lat=-33.45, origin_lng=-70.65,
                    destination_address='Calle Destino 456, Providencia', destination_lat=-33.4,
                    destination_lng=-70.6, cargo_description='Cajas', cargo_weight_kg=20)
        self.assertEqual(FreightCreate(**base).origin_address, base['origin_address'])
        for field in ['origin_address', 'destination_address']:
            for value in ['Mi ubicaci\u00f3n actual', 'Ubicaci\u00f3n seleccionada en el mapa',
                          'Punto de retiro del cliente', 'Direccion no registrada']:
                with self.assertRaises(ValidationError):
                    FreightCreate(**{**base, field: value})
