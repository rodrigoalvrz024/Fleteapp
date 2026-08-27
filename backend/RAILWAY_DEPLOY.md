# Despliegue del backend Muvv en Railway

Esta guia publica **solo** el backend FastAPI. Firebase Hosting y Supabase se
mantienen como estan.

## 1. Crear el servicio

1. Entra a [Railway](https://railway.app) y crea un proyecto vacio.
2. Selecciona **New > GitHub Repo** y elige `rodrigoalvrz024/Fleteapp`.
3. En el servicio creado abre **Settings > Build**.
4. Configura **Root Directory** como `/backend`.
5. Comprueba que Railway detecte `Dockerfile`.
6. En **Deploy**, configura:
   - Pre-deploy Command: `alembic upgrade head`
   - Healthcheck Path: `/health`
   - Healthcheck Timeout: `300`
   - Restart Policy: `Always` (requiere plan de pago).
7. En **Networking**, genera un dominio publico. Guardalo; sera el valor de
   `PUBLIC_API_URL` y `API_BASE_URL` de la app Flutter.

Railway ejecuta el pre-deploy antes de poner la nueva version en trafico. Si la
migracion falla, la version anterior sigue siendo la activa. El healthcheck
verifica que FastAPI **y la conexion a Supabase** esten disponibles antes de
publicar la version.

## 2. Variables del servicio

Abre **Variables > Raw Editor** y agrega las variables. Usa valores reales
solamente en Railway: no copies secretos al repositorio ni los pegues en chat.

```dotenv
APP_ENV=production
DATABASE_URL=postgresql://...SUPABASE_TRANSACTION_POOLER...?sslmode=require
SECRET_KEY=<cadena-aleatoria-de-al-menos-48-caracteres>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=1440
JWT_ISSUER=muvv-api
JWT_AUDIENCE=muvv-app
CORS_ORIGINS=https://muvv-dev.web.app,https://muvv-dev-public.web.app
FRONTEND_URL=https://muvv-dev.web.app
PUBLIC_API_URL=https://<tu-servicio>.up.railway.app
MAX_REQUEST_BODY_MB=10
RUN_STARTUP_MIGRATIONS=false

PILOT_MODE=true
PILOT_ALLOWED_EMAILS=<correo-cliente-piloto>,<correo-conductor-piloto>,<correo-ceo>
TERMS_VERSION=2026-08-26
PRIVACY_VERSION=2026-08-26

SUPABASE_URL=https://<tu-proyecto>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<service-role-key-de-supabase>
DRIVER_DOCUMENTS_BUCKET=<bucket-privado-existente>
DRIVER_DOCUMENT_MAX_MB=5
DRIVER_DOCUMENT_VIEW_EXPIRE_MINUTES=10
FREIGHT_EVIDENCE_MAX_MB=8
FREIGHT_EVIDENCE_VIEW_EXPIRE_MINUTES=10
CHAT_IMAGE_MAX_MB=5
CHAT_IMAGE_VIEW_EXPIRE_MINUTES=10

GOOGLE_MAPS_KEY=<clave-restringida-del-backend>
PRICING_QUOTE_EXPIRE_MINUTES=10
PRICING_ROUTE_MAX_RETRIES=2

TRANSBANK_ENVIRONMENT=integration
TRANSBANK_COMMERCE_CODE=
TRANSBANK_API_KEY=
ALLOW_SIMULATED_PAYMENTS=false

RESEND_API_KEY=
EMAIL_FROM=Muvv <onboarding@resend.dev>
PASSWORD_RESET_EXPIRE_MINUTES=30

ENABLE_DRIVER_PUSH_NOTIFICATIONS=false
NOTIFICATION_TASKS_ENABLED=false
```

Mantiene vacias las variables de Transbank, Resend y Firebase Admin mientras
esas integraciones no esten validadas en Railway. No actives Cloud Tasks: es
una integracion de Google Cloud y no es necesaria para publicar el piloto.

## 3. Primer despliegue y comprobacion

1. Aplica las variables y ejecuta el despliegue inicial desde Railway.
2. Revisa el log: debe aparecer la ejecucion exitosa de `alembic upgrade head`
   y luego Uvicorn escuchando el puerto entregado por Railway.
3. Abre `https://<tu-servicio>.up.railway.app/health`. Debe responder:

```json
{"status":"healthy","pilot_mode":true}
```

4. Verifica `https://<tu-servicio>.up.railway.app/docs` y confirma que existen
   las rutas de chat y `POST /auth/accept-legal-update`.
5. Solo despues actualiza `API_BASE_URL` en Flutter y recompila la app.

## 4. Operacion segura

- Railway debe desplegar desde `main` unicamente tras una revision.
- Conserva Supabase como base de datos y almacenamiento; no agregues una base
  Railway paralela.
- No configures `RUN_STARTUP_MIGRATIONS=true`: las migraciones deben ocurrir
  solo en el pre-deploy para evitar carreras entre instancias.
- Revisa Usage una vez por semana y configura un limite/alerta mensual en
  Railway. Las alertas avisan, pero no sustituyen la revision humana.
- Para el piloto real, deja `PILOT_MODE=true` y limita los correos invitados.
