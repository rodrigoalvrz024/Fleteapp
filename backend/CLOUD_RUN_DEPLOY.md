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
  --max-instances 2 `
  --memory 512Mi `
  --cpu 1 `
  --set-secrets DATABASE_URL=DATABASE_URL:latest,SECRET_KEY=SECRET_KEY:latest `
  --set-env-vars ALGORITHM=HS256,ACCESS_TOKEN_EXPIRE_MINUTES=10080,TRANSBANK_ENVIRONMENT=integration
```

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
