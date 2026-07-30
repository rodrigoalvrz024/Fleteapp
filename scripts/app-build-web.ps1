param(
  [string]$GoogleMapsApiKey = $env:GOOGLE_MAPS_API_KEY,
  [string]$ProjectId = $(if ([string]::IsNullOrWhiteSpace($env:PROJECT_ID)) { 'fleteapp-8d8f7' } else { $env:PROJECT_ID }),
  [string]$MapsWebKeyId = $env:GOOGLE_MAPS_WEB_KEY_ID,
  [string]$FirebaseWebApiKey = $env:FIREBASE_WEB_API_KEY,
  [string]$FirebaseWebAppId = $env:FIREBASE_WEB_APP_ID,
  [string]$FirebaseMessagingSenderId = $env:FIREBASE_MESSAGING_SENDER_ID,
  [string]$FirebaseProjectId = $(if ([string]::IsNullOrWhiteSpace($env:FIREBASE_PROJECT_ID)) { $ProjectId } else { $env:FIREBASE_PROJECT_ID }),
  [string]$FirebaseAuthDomain = $env:FIREBASE_AUTH_DOMAIN,
  [string]$FirebaseStorageBucket = $env:FIREBASE_STORAGE_BUCKET,
  [string]$ApiBaseUrl = $env:API_BASE_URL,
  [string]$PublicHomeUrl = $(if ([string]::IsNullOrWhiteSpace($env:PUBLIC_HOME_URL)) { $env:NEXT_PUBLIC_SITE_URL } else { $env:PUBLIC_HOME_URL })
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot 'mobile'
$flutterDefault = 'C:\flutter\bin\flutter.bat'
$gcloudDefault = Join-Path $env:LOCALAPPDATA 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'

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

function Get-GcloudCli {
  $command = Get-Command gcloud -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  if (Test-Path $gcloudDefault) {
    return $gcloudDefault
  }

  return $null
}

function Get-RestrictedMapsWebKey {
  if ([string]::IsNullOrWhiteSpace($MapsWebKeyId)) {
    return $null
  }

  $gcloud = Get-GcloudCli
  if (-not $gcloud) {
    return $null
  }

  $value = & $gcloud services api-keys get-key-string $MapsWebKeyId `
    --location global `
    --project $ProjectId `
    --format 'value(keyString)' 2>$null

  if ($LASTEXITCODE -ne 0) {
    return $null
  }

  return "$value".Trim()
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
  $GoogleMapsApiKey = Get-RestrictedMapsWebKey
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
$toolAppData = Join-Path $mobileDir '.tool_appdata'
$toolLocalAppData = Join-Path $mobileDir '.tool_localappdata'
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA

New-Item -ItemType Directory -Force -Path $toolAppData | Out-Null
New-Item -ItemType Directory -Force -Path $toolLocalAppData | Out-Null

Push-Location $mobileDir
try {
  $env:APPDATA = $toolAppData
  $env:LOCALAPPDATA = $toolLocalAppData
  $flutterArgs = @(
    'build',
    'web',
    '--release',
    "--web-define=GOOGLE_MAPS_API_KEY=$GoogleMapsApiKey"
  )

  $dartDefines = @{
    FIREBASE_WEB_API_KEY = $FirebaseWebApiKey
    FIREBASE_WEB_APP_ID = $FirebaseWebAppId
    FIREBASE_MESSAGING_SENDER_ID = $FirebaseMessagingSenderId
    FIREBASE_PROJECT_ID = $FirebaseProjectId
    FIREBASE_AUTH_DOMAIN = $FirebaseAuthDomain
    FIREBASE_STORAGE_BUCKET = $FirebaseStorageBucket
    API_BASE_URL = $ApiBaseUrl
    PUBLIC_HOME_URL = $PublicHomeUrl
  }

  foreach ($item in $dartDefines.GetEnumerator()) {
    if (-not [string]::IsNullOrWhiteSpace($item.Value)) {
      $flutterArgs += "--dart-define=$($item.Key)=$($item.Value)"
    }
  }

  & $flutter @flutterArgs
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  $env:APPDATA = $previousAppData
  $env:LOCALAPPDATA = $previousLocalAppData
  Pop-Location
}

$buildConfig = Join-Path $mobileDir 'build\web\config.js'
$encodedKey = $GoogleMapsApiKey | ConvertTo-Json -Compress
Set-Content -LiteralPath $buildConfig `
  -Value "window.MUVV_GOOGLE_MAPS_API_KEY = $encodedKey;" `
  -Encoding UTF8

Write-Host 'Build web generado con GOOGLE_MAPS_API_KEY en mobile/build/web/config.js.'
