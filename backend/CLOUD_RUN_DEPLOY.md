# Cloud Run deploy

This backend is prepared to run on Cloud Run with Supabase Postgres.

## Cost choice

For lowest cost, use `us-central1`. Cloud Run's free tier discount is based on Tier 1 pricing, and `us-central1` is Tier 1.

For lowest latency from Chile, use `southamerica-west1` (Santiago). It can cost a little more because it is Tier 2.

Recommended first deploy:

```powershell
$env:PROJECT_ID="your-gcp-project-id"
$env:REGION="us-central1"
$env:SERVICE="fleteapp-api"
```

## One-time setup

Install Google Cloud CLI, then run:

```powershell
gcloud auth login
gcloud config set project $env:PROJECT_ID
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com
```

Create secrets:

```powershell
printf "postgresql://postgres:YOUR_PASSWORD@db.YOUR_PROJECT.supabase.co:5432/postgres?sslmode=require" | gcloud secrets create DATABASE_URL --data-file=-
printf "change-me-to-a-long-random-secret" | gcloud secrets create SECRET_KEY --data-file=-
```

Optional, only if push notifications are needed:

```powershell
printf "PASTE_FIREBASE_JSON_ON_ONE_LINE" | gcloud secrets create FIREBASE_CREDENTIALS_JSON --data-file=-
```

## Deploy

From this `backend` folder:

```powershell
gcloud run deploy $env:SERVICE `
  --source . `
  --region $env:REGION `
  --allow-unauthenticated `
  --min-instances 0 `
  --max-instances 5 `
  --concurrency 25 `
  --memory 512Mi `
  --cpu 1 `
  --timeout 30s `
  --set-secrets DATABASE_URL=DATABASE_URL:latest,SECRET_KEY=SECRET_KEY:latest `
  --set-env-vars ALGORITHM=HS256,ACCESS_TOKEN_EXPIRE_MINUTES=10080,TRANSBANK_ENVIRONMENT=integration,RUN_STARTUP_MIGRATIONS=false,DB_POOL_SIZE=5,DB_MAX_OVERFLOW=2,DB_POOL_TIMEOUT_SECONDS=5,DB_CONNECT_TIMEOUT_SECONDS=10
```

The API does not run migrations automatically on every Cloud Run startup. This
keeps `/health` responsive even if the database is temporarily slow.

For the first deploy, or after schema changes, run migrations intentionally with
the same environment variables/secrets used by the service:

```powershell
python -m app.run_migrations
```

If you need a temporary Cloud Run revision to run migrations during deploy, add:

```powershell
--set-env-vars RUN_STARTUP_MIGRATIONS=true
```

Then deploy again with `RUN_STARTUP_MIGRATIONS=false` or without that variable.

If Firebase push notifications are needed, add this to the deploy command:

```powershell
--set-secrets FIREBASE_CREDENTIALS_JSON=FIREBASE_CREDENTIALS_JSON:latest
```

## Verify

Cloud Run prints the service URL after deployment. Test:

```powershell
curl https://YOUR_CLOUD_RUN_URL/health
curl https://YOUR_CLOUD_RUN_URL/docs
```

Then run Flutter against Cloud Run:

```powershell
flutter run --dart-define=API_BASE_URL=https://YOUR_CLOUD_RUN_URL
```
