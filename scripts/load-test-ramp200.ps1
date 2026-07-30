$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$testScript = Join-Path $repoRoot 'load-tests\k6\muvv-load.js'
$summaryDir = Join-Path $repoRoot 'reports\load-tests'

function Require-Command($Name, $InstallHint) {
  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $command) {
    $local = Join-Path $repoRoot ".local-tools\$Name\$Name.exe"
    if (Test-Path $local) {
      return $local
    }
    throw "No se encontro '$Name'. $InstallHint"
  }
  return $command.Source
}

function Require-Env($Name) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Name))) {
    throw "Falta definir `$env:$Name."
  }
}

if ($env:REGISTER_CLIENTS -ne 'true') {
  if ([string]::IsNullOrWhiteSpace($env:CLIENT_EMAILS)) {
    Require-Env 'CLIENT_EMAIL'
  }
  if ([string]::IsNullOrWhiteSpace($env:CLIENT_PASSWORDS)) {
    Require-Env 'CLIENT_PASSWORD'
  }
}

$k6 = Require-Command 'k6' 'Instalalo con: winget install GrafanaLabs.k6'

if ([string]::IsNullOrWhiteSpace($env:BASE_URL)) {
  $env:BASE_URL = 'https://fleteapp-api-i3wy5watea-uc.a.run.app'
}

$env:PROFILE = 'ramp200'
$env:WRITE_FREIGHTS = if ([string]::IsNullOrWhiteSpace($env:WRITE_FREIGHTS)) { 'false' } else { $env:WRITE_FREIGHTS }
$env:DRIVER_READS = if ([string]::IsNullOrWhiteSpace($env:DRIVER_READS)) { 'true' } else { $env:DRIVER_READS }

Write-Host "Ejecutando prueba ramp200 contra $env:BASE_URL."
Write-Host "WRITE_FREIGHTS=$env:WRITE_FREIGHTS"
Write-Host "DRIVER_READS=$env:DRIVER_READS"
Write-Host 'Duracion aproximada: 17 minutos.'

New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null
$summaryPath = Join-Path $summaryDir ("ramp200-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$k6Args = @('run', '--summary-export', $summaryPath)

if ($env:K6_QUIET -eq 'true') {
  $k6Args += '--quiet'
}

$k6Args += $testScript

& $k6 @k6Args
$exitCode = $LASTEXITCODE
Write-Host "Resumen JSON: $summaryPath"
exit $exitCode
