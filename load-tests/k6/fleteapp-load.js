import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || 'https://fleteapp-api-i3wy5watea-uc.a.run.app').replace(/\/$/, '');
const PROFILE = __ENV.PROFILE || 'smoke';
const WRITE_FREIGHTS = (__ENV.WRITE_FREIGHTS || 'false').toLowerCase() === 'true';
const DRIVER_READS = (__ENV.DRIVER_READS || 'true').toLowerCase() === 'true';
const CLIENT_EMAIL = __ENV.CLIENT_EMAIL;
const CLIENT_PASSWORD = __ENV.CLIENT_PASSWORD;
const DRIVER_EMAIL = __ENV.DRIVER_EMAIL;
const DRIVER_PASSWORD = __ENV.DRIVER_PASSWORD;
const DRIVER_EVERY = Number(__ENV.DRIVER_EVERY || 4);

export const errorRate = new Rate('fleteapp_errors');
export const freightCreates = new Counter('fleteapp_freight_creates');
export const freightCreateLatency = new Trend('fleteapp_freight_create_latency');
export const freightListLatency = new Trend('fleteapp_freight_list_latency');

export const options = buildOptions(PROFILE);

function buildOptions(profile) {
  if (profile === 'ramp200') {
    return {
      scenarios: {
        mixed_app_traffic: {
          executor: 'ramping-vus',
          stages: [
            { duration: '2m', target: 25 },
            { duration: '3m', target: 75 },
            { duration: '5m', target: 200 },
            { duration: '5m', target: 200 },
            { duration: '2m', target: 0 },
          ],
          gracefulRampDown: '30s',
        },
      },
      thresholds: {
        http_req_failed: ['rate<0.02'],
        http_req_duration: ['p(95)<1200', 'p(99)<2500'],
        fleteapp_errors: ['rate<0.02'],
        fleteapp_freight_list_latency: ['p(95)<1000'],
      },
    };
  }

  return {
    scenarios: {
      smoke: {
        executor: 'constant-vus',
        vus: Number(__ENV.VUS || 3),
        duration: __ENV.DURATION || '45s',
      },
    },
    thresholds: {
      http_req_failed: ['rate<0.05'],
      http_req_duration: ['p(95)<1500'],
      fleteapp_errors: ['rate<0.05'],
    },
  };
}

export function setup() {
  if (!CLIENT_EMAIL || !CLIENT_PASSWORD) {
    throw new Error('Debes definir CLIENT_EMAIL y CLIENT_PASSWORD como variables de entorno.');
  }

  const client = login(CLIENT_EMAIL, CLIENT_PASSWORD);
  const driver =
    DRIVER_READS && DRIVER_EMAIL && DRIVER_PASSWORD
      ? login(DRIVER_EMAIL, DRIVER_PASSWORD)
      : null;

  return { client, driver };
}

export default function (data) {
  const asDriver = data.driver && DRIVER_READS && __VU % DRIVER_EVERY === 0;
  if (asDriver) {
    driverReadFlow(data.driver);
    return;
  }
  clientFlow(data.client);
}

function login(email, password) {
  const res = http.post(
    `${BASE_URL}/auth/login`,
    JSON.stringify({ email, password }),
    {
      ...jsonHeaders(),
      tags: { name: 'POST /auth/login' },
    },
  );

  assertOk(res, 'login');
  const body = safeJson(res);
  if (!body.access_token) {
    throw new Error(`Login sin access_token para ${email}. HTTP ${res.status}.`);
  }

  return {
    email,
    token: body.access_token,
    role: body.user?.role || 'unknown',
  };
}

function clientFlow(client) {
  group('client read flow', () => {
    const headers = authHeaders(client.token);

    let res = http.get(`${BASE_URL}/users/me`, {
      headers,
      tags: { name: 'GET /users/me' },
    });
    assertOk(res, 'client me');

    res = http.get(`${BASE_URL}/freights`, {
      headers,
      tags: { name: 'GET /freights client' },
    });
    freightListLatency.add(res.timings.duration);
    assertOk(res, 'client freights');
  });

  if (WRITE_FREIGHTS) {
    group('client create freight', () => {
      const headers = authHeaders(client.token);
      const payload = freightPayload();
      const res = http.post(`${BASE_URL}/freights`, JSON.stringify(payload), {
        headers,
        tags: { name: 'POST /freights' },
      });
      freightCreateLatency.add(res.timings.duration);
      const ok = check(res, {
        'freight created': (r) => r.status === 201,
      });
      errorRate.add(!ok);
      if (ok) freightCreates.add(1);
    });
  }

  sleep(randomSleep());
}

function driverReadFlow(driver) {
  group('driver read flow', () => {
    const headers = authHeaders(driver.token);

    let res = http.get(`${BASE_URL}/drivers/me`, {
      headers,
      tags: { name: 'GET /drivers/me' },
    });
    assertOk(res, 'driver me');

    res = http.get(`${BASE_URL}/freights?status=available`, {
      headers,
      tags: { name: 'GET /freights available' },
    });
    freightListLatency.add(res.timings.duration);
    assertOkOrForbidden(res, 'driver available freights');
  });

  sleep(randomSleep());
}

function freightPayload() {
  const offset = (__VU * 0.001) + (__ITER * 0.0001);
  return {
    origin_address: `Load test origen VU ${__VU} ITER ${__ITER}`,
    origin_lat: -33.4489 + offset,
    origin_lng: -70.6693 + offset,
    destination_address: 'Load test destino Las Condes',
    destination_lat: -33.4146,
    destination_lng: -70.5856,
    cargo_description: 'Carga de prueba automatizada',
    cargo_weight_kg: 25,
    cargo_volume_m3: 1.2,
    requires_helpers: 0,
    is_urgent: false,
  };
}

function assertOk(res, label) {
  const ok = check(res, {
    [`${label} status 2xx`]: (r) => r.status >= 200 && r.status < 300,
  });
  errorRate.add(!ok);
  return ok;
}

function assertOkOrForbidden(res, label) {
  const ok = check(res, {
    [`${label} status 2xx or 403`]: (r) =>
      (r.status >= 200 && r.status < 300) || r.status === 403,
  });
  errorRate.add(!ok);
  return ok;
}

function safeJson(res) {
  try {
    return res.json();
  } catch (_) {
    return {};
  }
}

function jsonHeaders() {
  return {
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
  };
}

function authHeaders(token) {
  return {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };
}

function randomSleep() {
  return Math.random() * 2 + 0.5;
}
