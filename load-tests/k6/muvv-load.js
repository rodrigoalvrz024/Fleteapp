import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || 'https://fleteapp-api-i3wy5watea-uc.a.run.app').replace(/\/$/, '');
const PROFILE = __ENV.PROFILE || 'smoke';
const WRITE_FREIGHTS = (__ENV.WRITE_FREIGHTS || 'false').toLowerCase() === 'true';
const DRIVER_READS = (__ENV.DRIVER_READS || 'true').toLowerCase() === 'true';
const REGISTER_CLIENTS = (__ENV.REGISTER_CLIENTS || 'false').toLowerCase() === 'true';
const REGISTER_CLIENT_COUNT = Number(__ENV.REGISTER_CLIENT_COUNT || __ENV.VUS || 1);
const CLIENT_EMAIL = __ENV.CLIENT_EMAIL;
const CLIENT_PASSWORD = __ENV.CLIENT_PASSWORD;
const CLIENT_EMAILS = (__ENV.CLIENT_EMAILS || '')
  .split(',')
  .map((value) => value.trim())
  .filter(Boolean);
const CLIENT_PASSWORDS = (__ENV.CLIENT_PASSWORDS || '')
  .split(',')
  .map((value) => value.trim());
const DRIVER_EMAIL = __ENV.DRIVER_EMAIL;
const DRIVER_PASSWORD = __ENV.DRIVER_PASSWORD;
const DRIVER_EVERY = Number(__ENV.DRIVER_EVERY || 4);
const MAX_WRITE_ITERATIONS_PER_VU = Number(__ENV.MAX_WRITE_ITERATIONS_PER_VU || 1);
const LOAD_TEST_RUN_ID =
  __ENV.LOAD_TEST_RUN_ID || new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 14);

export const errorRate = new Rate('muvv_errors');
export const freightCreates = new Counter('muvv_freight_creates');
export const freightCreateLatency = new Trend('muvv_freight_create_latency');
export const freightListLatency = new Trend('muvv_freight_list_latency');

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
        muvv_errors: ['rate<0.02'],
        muvv_freight_list_latency: ['p(95)<1000'],
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
      muvv_errors: ['rate<0.05'],
    },
  };
}

export function setup() {
  if (!REGISTER_CLIENTS && CLIENT_EMAILS.length === 0 && (!CLIENT_EMAIL || !CLIENT_PASSWORD)) {
    throw new Error(
      'Debes definir CLIENT_EMAIL y CLIENT_PASSWORD, o CLIENT_EMAILS y CLIENT_PASSWORD/CLIENT_PASSWORDS.',
    );
  }

  const clients = REGISTER_CLIENTS
    ? registerClients(REGISTER_CLIENT_COUNT)
    : loginClientsFromEnv();
  const driver =
    DRIVER_READS && DRIVER_EMAIL && DRIVER_PASSWORD
      ? login(DRIVER_EMAIL, DRIVER_PASSWORD)
      : null;

  return { clients, driver };
}

export default function (data) {
  const asDriver = data.driver && DRIVER_READS && __VU % DRIVER_EVERY === 0;
  if (asDriver) {
    driverReadFlow(data.driver);
    return;
  }
  const client = data.clients[(__VU - 1) % data.clients.length];
  clientFlow(client);
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

function loginClientsFromEnv() {
  if (CLIENT_EMAILS.length === 0) {
    return [login(CLIENT_EMAIL, CLIENT_PASSWORD)];
  }

  return CLIENT_EMAILS.map((email, index) =>
    login(email, CLIENT_PASSWORDS[index] || CLIENT_PASSWORD),
  );
}

function registerClients(count) {
  const clients = [];
  for (let i = 0; i < count; i += 1) {
    const suffix = String(i + 1).padStart(3, '0');
    const email = `load.${LOAD_TEST_RUN_ID}.${suffix}@fletgo.com`;
    const password = `LoadTest${LOAD_TEST_RUN_ID}!`;
    const phoneSeed = LOAD_TEST_RUN_ID.replace(/\D/g, '').slice(-7).padStart(7, '0');
    const phone = `56${phoneSeed}${suffix}`;
    const res = http.post(
      `${BASE_URL}/auth/register`,
      JSON.stringify({
        email,
        phone,
        full_name: `Cliente Load ${suffix}`,
        password,
        role: 'client',
        accepts_terms: true,
        accepts_privacy: true,
      }),
      {
        ...jsonHeaders(),
        tags: { name: 'POST /auth/register load client' },
      },
    );

    const ok = check(res, {
      'load client registered': (r) => r.status === 201,
    });
    if (!ok) {
      throw new Error(`No se pudo registrar cliente load ${email}. HTTP ${res.status}.`);
    }
    const body = safeJson(res);
    if (!body.access_token) {
      throw new Error(`Registro sin access_token para ${email}. HTTP ${res.status}.`);
    }
    clients.push({
      email,
      token: body.access_token,
      role: body.user?.role || 'client',
    });
  }
  return clients;
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

  if (WRITE_FREIGHTS && __ITER < MAX_WRITE_ITERATIONS_PER_VU) {
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
    origin_address: `Load test ${LOAD_TEST_RUN_ID} origen VU ${__VU} ITER ${__ITER}`,
    origin_lat: -33.4489 + offset,
    origin_lng: -70.6693 + offset,
    destination_address: `Load test ${LOAD_TEST_RUN_ID} destino Las Condes`,
    destination_lat: -33.4146,
    destination_lng: -70.5856,
    cargo_description: `Carga de prueba automatizada ${LOAD_TEST_RUN_ID}`,
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
