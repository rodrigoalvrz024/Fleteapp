$ErrorActionPreference = 'Stop'

$projectId = if ([string]::IsNullOrWhiteSpace($env:PROJECT_ID)) { 'fleteapp-8d8f7' } else { $env:PROJECT_ID }
$region = if ([string]::IsNullOrWhiteSpace($env:REGION)) { 'us-central1' } else { $env:REGION }
$service = if ([string]::IsNullOrWhiteSpace($env:SERVICE)) { 'fleteapp-api' } else { $env:SERVICE }
$secretName = 'FIREBASE_CREDENTIALS_JSON'

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

function Get-CloudRunServiceAccount {
  $projectNumber = & $gcloud projects describe $projectId --format 'value(projectNumber)'
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($projectNumber)) {
    throw 'No se pudo obtener projectNumber.'
  }

  $runtimeServiceAccount = & $gcloud run services describe $service `
    --region $region `
    --project $projectId `
    --format 'value(spec.template.spec.serviceAccountName)'
  if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo leer el service account de Cloud Run.'
  }
  if ([string]::IsNullOrWhiteSpace($runtimeServiceAccount)) {
    return "$projectNumber-compute@developer.gserviceaccount.com"
  }
  return $runtimeServiceAccount
}

$gcloud = Get-GcloudCli

Write-Host "Configurar FIREBASE_CREDENTIALS_JSON para $service en $projectId/$region"
Write-Host "Primero descarga la clave desde Firebase > Configuracion del proyecto > Cuentas de servicio > Generar nueva clave privada."
Write-Host "No pegues el JSON en el chat. Pega aqui la ruta local del archivo descargado."
$jsonPath = Read-Host 'Ruta del archivo JSON'
$jsonPath = $jsonPath.Trim().Trim('"', "'")

if (-not (Test-Path -LiteralPath $jsonPath)) {
  throw "No existe el archivo: $jsonPath"
}

try {
  $credentials = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
} catch {
  throw 'El archivo no es un JSON valido.'
}

if ($credentials.type -ne 'service_account') {
  throw 'El JSON no parece ser una service account.'
}
if ([string]::IsNullOrWhiteSpace($credentials.project_id)) {
  throw 'El JSON no contiene project_id.'
}
if ([string]::IsNullOrWhiteSpace($credentials.client_email)) {
  throw 'El JSON no contiene client_email.'
}
if ([string]::IsNullOrWhiteSpace($credentials.private_key)) {
  throw 'El JSON no contiene private_key.'
}

Write-Host "Credencial detectada para project_id=$($credentials.project_id)"
Write-Host "client_email=$($credentials.client_email)"

& $gcloud secrets describe $secretName --project $projectId *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Creando secret $secretName..."
  Invoke-Gcloud secrets create $secretName `
    --project $projectId `
    --data-file $jsonPath
} else {
  Write-Host "Agregando nueva version al secret $secretName..."
  Invoke-Gcloud secrets versions add $secretName `
    --project $projectId `
    --data-file $jsonPath
}

$runtimeServiceAccount = Get-CloudRunServiceAccount
Write-Host "Runtime service account de Cloud Run: $runtimeServiceAccount"

Invoke-Gcloud secrets add-iam-policy-binding $secretName `
  --project $projectId `
  --member "serviceAccount:$runtimeServiceAccount" `
  --role roles/secretmanager.secretAccessor `
  --quiet

Write-Host "Actualizando Cloud Run para montar $secretName y activar push..."
Invoke-Gcloud run services update $service `
  --region $region `
  --project $projectId `
  --update-secrets "$secretName=${secretName}:latest" `
  --update-env-vars "ENABLE_DRIVER_PUSH_NOTIFICATIONS=true,NOTIFICATION_TASKS_ENABLED=true"

$serviceUrl = & $gcloud run services describe $service `
  --region $region `
  --project $projectId `
  --format 'value(status.url)'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($serviceUrl)) {
  throw 'No se pudo obtener URL de Cloud Run.'
}

Write-Host ""
Write-Host "Firebase Admin configurado."
Write-Host "Push a conductores activadas: true"
Write-Host "Backend: $serviceUrl"
Write-Host "Prueba health:"
Write-Host "curl.exe --ssl-no-revoke $serviceUrl/health"
