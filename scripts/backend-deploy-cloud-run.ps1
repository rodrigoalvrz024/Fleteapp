$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repoRoot 'backend'
$projectId = if ([string]::IsNullOrWhiteSpace($env:PROJECT_ID)) { 'fleteapp-8d8f7' } else { $env:PROJECT_ID }
$region = if ([string]::IsNullOrWhiteSpace($env:REGION)) { 'us-central1' } else { $env:REGION }
$service = if ([string]::IsNullOrWhiteSpace($env:SERVICE)) { 'fleteapp-api' } else { $env:SERVICE }
$maxInstances = if ([string]::IsNullOrWhiteSpace($env:MAX_INSTANCES)) { '5' } else { $env:MAX_INSTANCES }
$concurrency = if ([string]::IsNullOrWhiteSpace($env:CONCURRENCY)) { '15' } else { $env:CONCURRENCY }
$memory = if ([string]::IsNullOrWhiteSpace($env:MEMORY)) { '512Mi' } else { $env:MEMORY }
$cpu = if ([string]::IsNullOrWhiteSpace($env:CPU)) { '1' } else { $env:CPU }
$timeout = if ([string]::IsNullOrWhiteSpace($env:TIMEOUT)) { '30s' } else { $env:TIMEOUT }
$dbPoolSize = if ([string]::IsNullOrWhiteSpace($env:DB_POOL_SIZE)) { '8' } else { $env:DB_POOL_SIZE }
$dbMaxOverflow = if ([string]::IsNullOrWhiteSpace($env:DB_MAX_OVERFLOW)) { '2' } else { $env:DB_MAX_OVERFLOW }
$dbPoolTimeout = if ([string]::IsNullOrWhiteSpace($env:DB_POOL_TIMEOUT_SECONDS)) { '5' } else { $env:DB_POOL_TIMEOUT_SECONDS }
$dbConnectTimeout = if ([string]::IsNullOrWhiteSpace($env:DB_CONNECT_TIMEOUT_SECONDS)) { '10' } else { $env:DB_CONNECT_TIMEOUT_SECONDS }
$runStartupMigrations = if ([string]::IsNullOrWhiteSpace($env:RUN_STARTUP_MIGRATIONS)) { 'false' } else { $env:RUN_STARTUP_MIGRATIONS }
$driverPushNotifications = if ([string]::IsNullOrWhiteSpace($env:ENABLE_DRIVER_PUSH_NOTIFICATIONS)) { 'false' } else { $env:ENABLE_DRIVER_PUSH_NOTIFICATIONS }
$notificationTasksEnabled = if ([string]::IsNullOrWhiteSpace($env:NOTIFICATION_TASKS_ENABLED)) { 'false' } else { $env:NOTIFICATION_TASKS_ENABLED }
$cloudTasksLocation = if ([string]::IsNullOrWhiteSpace($env:CLOUD_TASKS_LOCATION)) { $region } else { $env:CLOUD_TASKS_LOCATION }
$cloudTasksQueue = if ([string]::IsNullOrWhiteSpace($env:CLOUD_TASKS_QUEUE)) { 'freight-notifications' } else { $env:CLOUD_TASKS_QUEUE }
$cloudTasksServiceAccount = if ([string]::IsNullOrWhiteSpace($env:CLOUD_TASKS_SERVICE_ACCOUNT)) { '' } else { $env:CLOUD_TASKS_SERVICE_ACCOUNT }
$cloudTasksTargetBaseUrl = if ([string]::IsNullOrWhiteSpace($env:CLOUD_TASKS_TARGET_BASE_URL)) { '' } else { $env:CLOUD_TASKS_TARGET_BASE_URL }
$cloudTasksAudience = if ([string]::IsNullOrWhiteSpace($env:CLOUD_TASKS_AUDIENCE)) { $cloudTasksTargetBaseUrl } else { $env:CLOUD_TASKS_AUDIENCE }

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

$gcloud = Get-GcloudCli

Write-Host "Desplegando backend $service en $projectId/$region..."
Write-Host "Cloud Run: max-instances=$maxInstances concurrency=$concurrency memory=$memory cpu=$cpu timeout=$timeout"
Write-Host "Postgres pool por instancia: pool_size=$dbPoolSize max_overflow=$dbMaxOverflow"
Write-Host "RUN_STARTUP_MIGRATIONS=$runStartupMigrations"
Write-Host "ENABLE_DRIVER_PUSH_NOTIFICATIONS=$driverPushNotifications"
Write-Host "NOTIFICATION_TASKS_ENABLED=$notificationTasksEnabled"
& $gcloud run deploy $service `
  --source $backendDir `
  --region $region `
  --project $projectId `
  --allow-unauthenticated `
  --min-instances 0 `
  --max-instances $maxInstances `
  --concurrency $concurrency `
  --memory $memory `
  --cpu $cpu `
  --timeout $timeout `
  --update-env-vars "RUN_STARTUP_MIGRATIONS=$runStartupMigrations,ENABLE_DRIVER_PUSH_NOTIFICATIONS=$driverPushNotifications,NOTIFICATION_TASKS_ENABLED=$notificationTasksEnabled,GOOGLE_CLOUD_PROJECT=$projectId,CLOUD_TASKS_LOCATION=$cloudTasksLocation,CLOUD_TASKS_QUEUE=$cloudTasksQueue,CLOUD_TASKS_SERVICE_ACCOUNT=$cloudTasksServiceAccount,CLOUD_TASKS_TARGET_BASE_URL=$cloudTasksTargetBaseUrl,CLOUD_TASKS_AUDIENCE=$cloudTasksAudience,DB_POOL_SIZE=$dbPoolSize,DB_MAX_OVERFLOW=$dbMaxOverflow,DB_POOL_TIMEOUT_SECONDS=$dbPoolTimeout,DB_CONNECT_TIMEOUT_SECONDS=$dbConnectTimeout"

if ($LASTEXITCODE -ne 0) {
  throw 'No se pudo desplegar Cloud Run.'
}

$serviceUrl = & $gcloud run services describe $service `
  --region $region `
  --project $projectId `
  --format 'value(status.url)'

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($serviceUrl)) {
  throw 'Deploy realizado, pero no se pudo obtener la URL del servicio.'
}

Write-Host "Backend desplegado: $serviceUrl"
Write-Host "Prueba health:"
Write-Host "curl.exe --ssl-no-revoke $serviceUrl/health"
