param(
  [string]$EnvFile = (Join-Path $PSScriptRoot '..\backend\.env')
)

$ErrorActionPreference = 'Stop'

function Read-EnvValues {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "No se encontro el archivo de entorno: $Path"
  }

  $values = @{}
  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#') -or -not $trimmed.Contains('=')) {
      continue
    }
    $pair = $trimmed.Split('=', 2)
    $values[$pair[0].Trim()] = $pair[1].Trim()
  }
  return $values
}

$values = Read-EnvValues -Path $EnvFile
$required = @(
  'DATABASE_URL',
  'SECRET_KEY',
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'DRIVER_DOCUMENTS_BUCKET',
  'GOOGLE_MAPS_KEY'
)

$missing = @()
foreach ($name in $required) {
  $value = $values[$name]
  if ([string]::IsNullOrWhiteSpace($value) -or $value -match 'YOUR_|change-me') {
    $missing += $name
  }
}

if ($values['SECRET_KEY'] -and $values['SECRET_KEY'].Length -lt 32) {
  $missing += 'SECRET_KEY (debe tener al menos 32 caracteres)'
}

Write-Host 'Preflight Railway para Muvv'
Write-Host "Archivo revisado: $EnvFile"
if ($missing.Count -gt 0) {
  Write-Host ''
  Write-Host 'Faltan o deben corregirse estas variables:' -ForegroundColor Yellow
  $missing | ForEach-Object { Write-Host "- $_" -ForegroundColor Yellow }
  exit 1
}

Write-Host 'Variables esenciales presentes. No se mostraron secretos.' -ForegroundColor Green
Write-Host 'En Railway configura tambien APP_ENV=production, RUN_STARTUP_MIGRATIONS=false,'
Write-Host 'PILOT_MODE=true, PILOT_ALLOWED_EMAILS y los dominios reales en CORS_ORIGINS.'
