$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectId = if ([string]::IsNullOrWhiteSpace($env:PROJECT_ID)) { 'fleteapp-8d8f7' } else { $env:PROJECT_ID }
$secretName = if ([string]::IsNullOrWhiteSpace($env:DATABASE_URL_SECRET)) { 'DATABASE_URL' } else { $env:DATABASE_URL_SECRET }
$sqlFile = if ([string]::IsNullOrWhiteSpace($env:SQL_FILE)) {
  Join-Path $repoRoot 'backend\sql\20260707_enable_public_rls.sql'
} else {
  $env:SQL_FILE
}
$python = Join-Path $repoRoot 'backend\venv\Scripts\python.exe'
$runner = Join-Path $PSScriptRoot 'apply-sql-file.py'

function Get-GcloudCli {
  $command = Get-Command gcloud -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $default = Join-Path $env:LOCALAPPDATA 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'
  if (Test-Path $default) {
    return $default
  }

  throw 'No se encontro gcloud. Abre una nueva PowerShell o revisa Google Cloud SDK.'
}

if (-not (Test-Path $python)) {
  throw "No se encontro Python del backend en $python"
}
if (-not (Test-Path $sqlFile)) {
  throw "No se encontro el archivo SQL en $sqlFile"
}

$gcloud = Get-GcloudCli

Write-Host "Aplicando hardening RLS de Supabase con secret $secretName en proyecto $projectId..."
Write-Host "SQL: $sqlFile"
Write-Host 'El DATABASE_URL se lee desde Secret Manager y no se imprime.'

$databaseUrl = & $gcloud secrets versions access latest `
  --secret $secretName `
  --project $projectId

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($databaseUrl)) {
  throw "No se pudo leer el secret $secretName desde Secret Manager."
}

try {
  $env:DATABASE_URL = "$databaseUrl".Trim()
  $env:SQL_FILE = (Resolve-Path $sqlFile).Path
  & $python $runner
  if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo aplicar el SQL de RLS.'
  }
} finally {
  Remove-Item Env:\DATABASE_URL -ErrorAction SilentlyContinue
  Remove-Item Env:\SQL_FILE -ErrorAction SilentlyContinue
}

Write-Host 'RLS hardening aplicado. Refresca Supabase Security Advisor para verificar.'
