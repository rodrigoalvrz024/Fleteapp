$ErrorActionPreference = 'Stop'

$projectId = if ([string]::IsNullOrWhiteSpace($env:PROJECT_ID)) { 'fleteapp-8d8f7' } else { $env:PROJECT_ID }
$region = if ([string]::IsNullOrWhiteSpace($env:REGION)) { 'us-central1' } else { $env:REGION }
$service = if ([string]::IsNullOrWhiteSpace($env:SERVICE)) { 'fleteapp-api' } else { $env:SERVICE }

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

function ConvertFrom-SecureInput {
  param([securestring]$SecureValue)
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Invoke-Gcloud {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  & $gcloud @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Fallo gcloud $($Arguments -join ' ')"
  }
}

$gcloud = Get-GcloudCli

Write-Host "Actualizar DATABASE_URL para $service en $projectId/$region"
Write-Host "Pega el Transaction pooler connection string de Supabase. No se guardara en archivos."
$secureDatabaseUrl = Read-Host -AsSecureString 'DATABASE_URL'
$databaseUrl = ConvertFrom-SecureInput $secureDatabaseUrl

if ([string]::IsNullOrWhiteSpace($databaseUrl)) {
  throw 'DATABASE_URL no puede estar vacio.'
}
$databaseUrl = $databaseUrl.Trim()
$databaseUrl = $databaseUrl.Trim('"', "'")
$databaseUrl = $databaseUrl -replace '\s+', ''
$databaseUrl = $databaseUrl -replace 'sslmode=%22require%22', 'sslmode=require'
$databaseUrl = $databaseUrl -replace 'sslmode="require"', 'sslmode=require'
$databaseUrl = $databaseUrl -replace "sslmode='require'", 'sslmode=require'
$databaseUrl = $databaseUrl -replace 'sslmode=%27require%27', 'sslmode=require'
if (-not $databaseUrl.StartsWith('postgresql://')) {
  throw 'DATABASE_URL debe comenzar con postgresql://'
}
if ($databaseUrl -notmatch 'pooler\.supabase\.com') {
  Write-Host "Aviso: la URL no parece ser del pooler de Supabase. Revisa que hayas copiado Transaction pooler."
}
if ($databaseUrl -notmatch 'sslmode=require') {
  $separator = if ($databaseUrl.Contains('?')) { '&' } else { '?' }
  $databaseUrl = "$databaseUrl${separator}sslmode=require"
  Write-Host "Se agrego sslmode=require a la URL."
}

& $gcloud secrets describe DATABASE_URL --project $projectId *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Creando secret DATABASE_URL..."
  $databaseUrl | & $gcloud secrets create DATABASE_URL --project $projectId --data-file=-
  if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo crear DATABASE_URL.'
  }
} else {
  Write-Host "Agregando nueva version al secret DATABASE_URL..."
  $databaseUrl | & $gcloud secrets versions add DATABASE_URL --project $projectId --data-file=-
  if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo agregar version a DATABASE_URL.'
  }
}

Write-Host "Forzando nueva revision de Cloud Run para tomar DATABASE_URL:latest..."
Invoke-Gcloud run services update $service `
  --region $region `
  --project $projectId `
  --update-secrets DATABASE_URL=DATABASE_URL:latest

$serviceUrl = & $gcloud run services describe $service `
  --region $region `
  --project $projectId `
  --format 'value(status.url)'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($serviceUrl)) {
  throw 'No se pudo obtener URL de Cloud Run.'
}

Write-Host ""
Write-Host "DATABASE_URL actualizado."
Write-Host "Backend: $serviceUrl"
Write-Host "Prueba health:"
Write-Host "curl.exe --ssl-no-revoke $serviceUrl/health"
