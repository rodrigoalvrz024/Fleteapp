param(
  [string]$GoogleMapsApiKey = $env:GOOGLE_MAPS_API_KEY
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot 'mobile'
$flutterDefault = 'C:\flutter\bin\flutter.bat'

function Get-FlutterCli {
  $command = Get-Command flutter -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  if (Test-Path $flutterDefault) {
    return $flutterDefault
  }

  throw 'No se encontro Flutter CLI. Revisa que Flutter este instalado o agrega flutter al PATH.'
}

function Read-PlainSecret([securestring]$Secret) {
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Test-GoogleMapsApiKey([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }

  if ($Value.Length -lt 20) {
    return $false
  }

  return $Value -notmatch '[\x00-\x1F\x7F]'
}

if (-not (Test-Path $mobileDir)) {
  throw "No se encontro la carpeta mobile en $mobileDir."
}

if ([string]::IsNullOrWhiteSpace($GoogleMapsApiKey)) {
  Write-Host 'Configurar GOOGLE_MAPS_API_KEY para la app web'
  Write-Host 'Pegala aqui. No la pegues en el chat.'
  $GoogleMapsApiKey = Read-PlainSecret (Read-Host 'GOOGLE_MAPS_API_KEY' -AsSecureString)
}

if ([string]::IsNullOrWhiteSpace($GoogleMapsApiKey)) {
  throw 'No se ingreso GOOGLE_MAPS_API_KEY. No se construira la app web.'
}

if (-not (Test-GoogleMapsApiKey $GoogleMapsApiKey)) {
  throw 'La GOOGLE_MAPS_API_KEY ingresada no parece valida. Copia la clave completa desde Google Cloud; si PowerShell no pega con Ctrl+V, usa clic derecho o define $env:GOOGLE_MAPS_API_KEY antes de ejecutar el script.'
}

$flutter = Get-FlutterCli

Push-Location $mobileDir
try {
  & $flutter build web --release "--web-define=GOOGLE_MAPS_API_KEY=$GoogleMapsApiKey"
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  Pop-Location
}

$buildConfig = Join-Path $mobileDir 'build\web\config.js'
$encodedKey = $GoogleMapsApiKey | ConvertTo-Json -Compress
Set-Content -LiteralPath $buildConfig `
  -Value "window.FLETEAPP_GOOGLE_MAPS_API_KEY = $encodedKey;" `
  -Encoding UTF8

Write-Host 'Build web generado con GOOGLE_MAPS_API_KEY en mobile/build/web/config.js.'
