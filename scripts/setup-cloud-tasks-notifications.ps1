$ErrorActionPreference = 'Stop'

$projectId = if ([string]::IsNullOrWhiteSpace($env:PROJECT_ID)) { 'fleteapp-8d8f7' } else { $env:PROJECT_ID }
$region = if ([string]::IsNullOrWhiteSpace($env:REGION)) { 'us-central1' } else { $env:REGION }
$service = if ([string]::IsNullOrWhiteSpace($env:SERVICE)) { 'fleteapp-api' } else { $env:SERVICE }
$queue = if ([string]::IsNullOrWhiteSpace($env:CLOUD_TASKS_QUEUE)) { 'freight-notifications' } else { $env:CLOUD_TASKS_QUEUE }
$invokerAccountName = if ([string]::IsNullOrWhiteSpace($env:CLOUD_TASKS_SERVICE_ACCOUNT_NAME)) { 'fleteapp-tasks-invoker' } else { $env:CLOUD_TASKS_SERVICE_ACCOUNT_NAME }
$invokerAccountEmail = "$invokerAccountName@$projectId.iam.gserviceaccount.com"

function Get-GcloudCli {
  $command = Get-Command gcloud -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $default = Join-Path $env:LOCALAPPDATA 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'
  if (Test-Path $default) {
    return $default
  }

  throw 'No se encontro gcloud. Abre una nueva PowerShell despues de instalar Google Cloud SDK, o revisa la instalacion.'
}

function Invoke-Gcloud {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  & $gcloud @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Fallo gcloud $($Arguments -join ' ')"
  }
}

$gcloud = Get-GcloudCli

Write-Host "Configurando Cloud Tasks para $service en $projectId/$region..."

Invoke-Gcloud services enable cloudtasks.googleapis.com --project $projectId

$projectNumber = & $gcloud projects describe $projectId --format 'value(projectNumber)'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($projectNumber)) {
  throw 'No se pudo obtener projectNumber.'
}

& $gcloud iam service-accounts describe $invokerAccountEmail --project $projectId *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Creando service account $invokerAccountEmail..."
  Invoke-Gcloud iam service-accounts create $invokerAccountName `
    --project $projectId `
    --display-name 'muvv Cloud Tasks Invoker'
} else {
  Write-Host "Service account ya existe: $invokerAccountEmail"
}

& $gcloud tasks queues describe $queue --location $region --project $projectId *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Creando cola $queue..."
  Invoke-Gcloud tasks queues create $queue `
    --location $region `
    --project $projectId `
    --max-dispatches-per-second 5 `
    --max-concurrent-dispatches 10 `
    --max-attempts 5 `
    --min-backoff 10s `
    --max-backoff 300s
} else {
  Write-Host "Actualizando limites de cola $queue..."
  Invoke-Gcloud tasks queues update $queue `
    --location $region `
    --project $projectId `
    --max-dispatches-per-second 5 `
    --max-concurrent-dispatches 10 `
    --max-attempts 5 `
    --min-backoff 10s `
    --max-backoff 300s
}

$runtimeServiceAccount = & $gcloud run services describe $service `
  --region $region `
  --project $projectId `
  --format 'value(spec.template.spec.serviceAccountName)'
if ($LASTEXITCODE -ne 0) {
  throw 'No se pudo leer el service account de Cloud Run.'
}
if ([string]::IsNullOrWhiteSpace($runtimeServiceAccount)) {
  $runtimeServiceAccount = "$projectNumber-compute@developer.gserviceaccount.com"
}

Write-Host "Runtime service account de Cloud Run: $runtimeServiceAccount"

Invoke-Gcloud projects add-iam-policy-binding $projectId `
  --member "serviceAccount:$runtimeServiceAccount" `
  --role roles/cloudtasks.enqueuer `
  --quiet

Invoke-Gcloud run services add-iam-policy-binding $service `
  --region $region `
  --project $projectId `
  --member "serviceAccount:$invokerAccountEmail" `
  --role roles/run.invoker `
  --quiet

$tasksServiceAgent = "service-$projectNumber@gcp-sa-cloudtasks.iam.gserviceaccount.com"
Invoke-Gcloud projects add-iam-policy-binding $projectId `
  --member "serviceAccount:$tasksServiceAgent" `
  --role roles/cloudtasks.serviceAgent `
  --quiet

Invoke-Gcloud iam service-accounts add-iam-policy-binding $invokerAccountEmail `
  --project $projectId `
  --member "serviceAccount:$tasksServiceAgent" `
  --role roles/iam.serviceAccountUser `
  --quiet

$serviceUrl = & $gcloud run services describe $service `
  --region $region `
  --project $projectId `
  --format 'value(status.url)'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($serviceUrl)) {
  throw 'No se pudo obtener URL de Cloud Run.'
}

$enableDriverPushNotifications = if ([string]::IsNullOrWhiteSpace($env:ENABLE_DRIVER_PUSH_NOTIFICATIONS)) { 'true' } else { $env:ENABLE_DRIVER_PUSH_NOTIFICATIONS }
$firebaseSecretName = & $gcloud secrets list `
  --project $projectId `
  --filter 'name:FIREBASE_CREDENTIALS_JSON' `
  --format 'value(name)'
if ([string]::IsNullOrWhiteSpace($firebaseSecretName) -and [string]::IsNullOrWhiteSpace($env:ENABLE_DRIVER_PUSH_NOTIFICATIONS)) {
  $enableDriverPushNotifications = 'false'
  Write-Host "Aviso: no existe FIREBASE_CREDENTIALS_JSON. Cloud Tasks queda configurado, pero las push quedan apagadas hasta crear ese secret."
}

Invoke-Gcloud run services update $service `
  --region $region `
  --project $projectId `
  --update-env-vars "ENABLE_DRIVER_PUSH_NOTIFICATIONS=$enableDriverPushNotifications,NOTIFICATION_TASKS_ENABLED=true,GOOGLE_CLOUD_PROJECT=$projectId,CLOUD_TASKS_LOCATION=$region,CLOUD_TASKS_QUEUE=$queue,CLOUD_TASKS_SERVICE_ACCOUNT=$invokerAccountEmail,CLOUD_TASKS_TARGET_BASE_URL=$serviceUrl,CLOUD_TASKS_AUDIENCE=$serviceUrl"

Write-Host ""
Write-Host "Cloud Tasks listo."
Write-Host "Cola: $queue"
Write-Host "Service account de tareas: $invokerAccountEmail"
Write-Host "Push a conductores activadas: $enableDriverPushNotifications"
Write-Host "Endpoint interno: $serviceUrl/internal/tasks/freights/{id}/notify-drivers"
