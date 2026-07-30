# Muvv: implementacion en cuenta Google nueva

Esta guia deja Muvv preparado para una cuenta Google/Firebase nueva, manteniendo el gasto al minimo durante desarrollo.

## Estrategia recomendada ahora

Usar Google solo para Firebase Hosting, Firebase config mobile, FCM/Analytics y pruebas controladas. Mantener backend y base fuera de GCP mientras no haya ingresos:

- Supabase Free: Postgres y storage de prueba.
- Render Free: backend FastAPI para demos.
- Firebase Spark o Vercel Hobby: web publica/app web.
- Sin Secret Manager, Cloud Run, Cloud Tasks, Cloud Functions ni Artifact Registry para desarrollo diario.

Si decides usar los USD 300 de una cuenta nueva, tratala como laboratorio temporal. No la uses como dependencia permanente hasta que haya piloto real o ingresos.

## 1. Crear proyecto Firebase/GCP nuevo

1. Entra con la cuenta nueva.
2. Crea un proyecto, por ejemplo `muvv-dev-123`.
3. Si quieres cero gasto real, mantente en Firebase Spark y no actives billing.
4. Si quieres usar los USD 300, activa el free trial, pero crea presupuesto/alertas desde el dia 1.

## 2. Cargar variables locales del nuevo proyecto

Copia el ejemplo:

```powershell
Copy-Item .\scripts\new-google-account.env.example.ps1 .\scripts\new-google-account.env.ps1
```

Edita `scripts\new-google-account.env.ps1` y cambia:

- `PROJECT_ID`
- `FIREBASE_WEB_API_KEY`
- `FIREBASE_WEB_APP_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `NEXT_PUBLIC_API_URL`
- `API_BASE_URL`

Carga el entorno:

```powershell
. .\scripts\new-google-account.env.ps1
```

Diagnostico local:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-new-google-account-readiness.ps1
```

Si falla por referencias antiguas, revisa si son defaults de compatibilidad o URLs que aun debes reemplazar antes de publicar.

## 3. Registrar apps Android/iOS en Firebase

Con `PROJECT_ID` cargado:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-firebase-muvv-apps.ps1
```

Esto crea o reutiliza:

- Android package: `cl.muvv.app`
- iOS bundle: `cl.muvv.app`

Y descarga:

- `mobile/android/app/google-services.json`
- `mobile/ios/Runner/GoogleService-Info.plist`

## 4. Configurar Hosting targets

Si usas Firebase Hosting:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\web-public-create-site.ps1
```

Este script asocia:

- target `app` -> `$env:FIREBASE_APP_SITE_ID`
- target `public` -> `$env:FIREBASE_PUBLIC_SITE_ID`

## 5. Desplegar web publica

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\web-public-deploy.ps1
```

El build usa estas variables si estan cargadas:

- `NEXT_PUBLIC_SITE_URL`
- `NEXT_PUBLIC_APP_URL`
- `NEXT_PUBLIC_API_URL`

## 6. Desplegar app web Flutter

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\app-deploy.ps1
```

El build usa:

- `PROJECT_ID`
- `API_BASE_URL`
- `GOOGLE_MAPS_API_KEY`
- `FIREBASE_WEB_API_KEY`
- `FIREBASE_WEB_APP_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_STORAGE_BUCKET`
- `API_BASE_URL`
- `PUBLIC_HOME_URL`

## 7. Backend sin Secret Manager

Para gasto minimo, usa Render Free:

1. Crea un Web Service desde el repo.
2. Root directory: `backend`.
3. Build command:

```text
pip install -r requirements.txt
```

4. Start command:

```text
uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

5. Variables en Render:

```text
DATABASE_URL=postgresql://...
SECRET_KEY=...
CORS_ORIGINS=https://TU_APP.web.app,https://TU_PUBLIC.web.app,http://localhost:3000,http://127.0.0.1:3000
FRONTEND_URL=https://TU_APP.web.app
PUBLIC_API_URL=https://TU_BACKEND.onrender.com
ALLOW_SIMULATED_PAYMENTS=true
ENABLE_DRIVER_PUSH_NOTIFICATIONS=false
NOTIFICATION_TASKS_ENABLED=false
```

No uses Secret Manager para esta etapa.

## 8. Si usas GCP con trial

Solo para pruebas:

- Cloud Run con `min-instances=0`.
- `max-instances=1` o `2`.
- No Secret Manager; usa variables de entorno de Cloud Run para dev.
- Politica de limpieza de Artifact Registry:

```powershell
gcloud artifacts repositories set-cleanup-policies cloud-run-source-deploy `
  --project=$env:PROJECT_ID `
  --location=$env:REGION `
  --policy=infra\artifact-registry-cleanup-policy.json `
  --no-dry-run
```

- Presupuesto bajo y alertas desde el primer dia.

## 9. Checklist antes de publicar

- Android release keystore creado.
- SHA-1/SHA-256 release agregados a Firebase.
- Google Maps con cuotas bajas y keys restringidas.
- Dominio real configurado.
- Politicas legales revisadas.
- Datos reales protegidos y documentos en storage privado.

## 10. Comando rapido de diagnostico

Para buscar restos del proyecto viejo:

```powershell
rg -n "fleteapp-8d8f7|591141449914|fleteapp-api|fleteapp-public" .
```
