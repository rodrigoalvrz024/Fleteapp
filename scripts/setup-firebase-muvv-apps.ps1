param(
  [string]$ProjectId = $(if ([string]::IsNullOrWhiteSpace($env:PROJECT_ID)) { 'fleteapp-8d8f7' } else { $env:PROJECT_ID }),
  [string]$AndroidPackageName = $(if ([string]::IsNullOrWhiteSpace($env:ANDROID_PACKAGE_NAME)) { 'cl.muvv.app' } else { $env:ANDROID_PACKAGE_NAME }),
  [string]$IosBundleId = $(if ([string]::IsNullOrWhiteSpace($env:IOS_BUNDLE_ID)) { 'cl.muvv.app' } else { $env:IOS_BUNDLE_ID }),
  [string]$AndroidDisplayName = $(if ([string]::IsNullOrWhiteSpace($env:ANDROID_DISPLAY_NAME)) { 'Muvv Android' } else { $env:ANDROID_DISPLAY_NAME }),
  [string]$IosDisplayName = $(if ([string]::IsNullOrWhiteSpace($env:IOS_DISPLAY_NAME)) { 'Muvv iOS' } else { $env:IOS_DISPLAY_NAME }),
  [string]$AndroidSha1 = $env:ANDROID_SHA1
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$androidConfigPath = Join-Path $repoRoot 'mobile\android\app\google-services.json'
$iosConfigPath = Join-Path $repoRoot 'mobile\ios\Runner\GoogleService-Info.plist'

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

function Get-AuthHeaders {
  $token = & $gcloud auth print-access-token
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'No se pudo obtener access token con gcloud auth print-access-token.'
  }

  return @{
    Authorization = "Bearer $token"
    'x-goog-user-project' = $ProjectId
  }
}

function Invoke-FirebaseApi {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    [object]$Body = $null
  )

  $uri = "https://firebase.googleapis.com/v1beta1/$Path"
  $params = @{
    Uri = $uri
    Headers = $headers
    Method = $Method
  }
  if ($null -ne $Body) {
    $params.ContentType = 'application/json'
    $params.Body = ($Body | ConvertTo-Json -Depth 10)
  }

  Invoke-RestMethod @params
}

function Wait-FirebaseOperation {
  param([Parameter(Mandatory = $true)][object]$Operation)

  if (-not $Operation.name) {
    return
  }

  for ($attempt = 1; $attempt -le 30; $attempt += 1) {
    $result = Invoke-FirebaseApi -Method Get -Path $Operation.name
    if ($result.done) {
      if ($result.error) {
        throw "Operacion Firebase fallo: $($result.error.message)"
      }
      return
    }
    Start-Sleep -Seconds 3
  }

  throw "La operacion Firebase no termino a tiempo: $($Operation.name)"
}

function Get-AndroidApp {
  $apps = Invoke-FirebaseApi -Method Get -Path "projects/$ProjectId/androidApps"
  @($apps.apps) | Where-Object { $_.packageName -eq $AndroidPackageName } | Select-Object -First 1
}

function Get-IosApp {
  $apps = Invoke-FirebaseApi -Method Get -Path "projects/$ProjectId/iosApps"
  @($apps.apps) | Where-Object { $_.bundleId -eq $IosBundleId } | Select-Object -First 1
}

function Save-ConfigFile {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigName,
    [Parameter(Mandatory = $true)][string]$OutputPath
  )

  $config = Invoke-FirebaseApi -Method Get -Path $ConfigName
  if ([string]::IsNullOrWhiteSpace($config.configFileContents)) {
    throw "Firebase no devolvio configFileContents para $ConfigName."
  }

  $bytes = [Convert]::FromBase64String($config.configFileContents)
  [System.IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
  [System.IO.File]::WriteAllBytes($OutputPath, $bytes)
}

function Resolve-DebugSha1 {
  if (-not [string]::IsNullOrWhiteSpace($AndroidSha1)) {
    return $AndroidSha1
  }

  $debugKeystore = Join-Path $env:USERPROFILE '.android\debug.keystore'
  if (-not (Test-Path $debugKeystore)) {
    return ''
  }

  $keytool = Get-Command keytool -ErrorAction SilentlyContinue
  if (-not $keytool) {
    $androidStudioKeytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
    if (Test-Path $androidStudioKeytool) {
      $keytool = [pscustomobject]@{ Source = $androidStudioKeytool }
    }
  }

  if (-not $keytool) {
    return ''
  }

  $shaLine = & $keytool.Source -list -v -keystore $debugKeystore -alias androiddebugkey -storepass android -keypass android |
    Select-String -Pattern 'SHA1:' |
    Select-Object -First 1
  if (-not $shaLine) {
    return ''
  }

  return $shaLine.ToString().Split(':', 2)[1].Trim()
}

$gcloud = Get-GcloudCli
$headers = Get-AuthHeaders

Write-Host "Configurando Firebase apps para $ProjectId..."
Write-Host "Android package: $AndroidPackageName"
Write-Host "iOS bundle id: $IosBundleId"

$androidApp = Get-AndroidApp
if (-not $androidApp) {
  Write-Host "Creando Android app $AndroidPackageName..."
  $operation = Invoke-FirebaseApi -Method Post -Path "projects/$ProjectId/androidApps" -Body @{
    displayName = $AndroidDisplayName
    packageName = $AndroidPackageName
  }
  Wait-FirebaseOperation -Operation $operation
  $androidApp = Get-AndroidApp
}
if (-not $androidApp) {
  throw 'No se pudo crear o encontrar la app Android en Firebase.'
}

$sha1 = Resolve-DebugSha1
if (-not [string]::IsNullOrWhiteSpace($sha1)) {
  $shaList = Invoke-FirebaseApi -Method Get -Path "$($androidApp.name)/sha"
  $existingSha = @($shaList.certificates) | Where-Object { $_.shaHash -replace ':', '' -ieq ($sha1 -replace ':', '') } | Select-Object -First 1
  if (-not $existingSha) {
    Write-Host 'Agregando SHA-1 debug a Android app...'
    Invoke-FirebaseApi -Method Post -Path "$($androidApp.name)/sha" -Body @{
      certType = 'SHA_1'
      shaHash = $sha1
    } | Out-Null
  } else {
    Write-Host 'SHA-1 debug ya existe en Android app.'
  }
} else {
  Write-Host 'Aviso: no se pudo detectar SHA-1 debug local. Agregalo despues para Maps/Firebase Android.'
}

$iosApp = Get-IosApp
if (-not $iosApp) {
  Write-Host "Creando iOS app $IosBundleId..."
  $operation = Invoke-FirebaseApi -Method Post -Path "projects/$ProjectId/iosApps" -Body @{
    displayName = $IosDisplayName
    bundleId = $IosBundleId
  }
  Wait-FirebaseOperation -Operation $operation
  $iosApp = Get-IosApp
}
if (-not $iosApp) {
  throw 'No se pudo crear o encontrar la app iOS en Firebase.'
}

Write-Host 'Descargando google-services.json...'
Save-ConfigFile -ConfigName "$($androidApp.name)/config" -OutputPath $androidConfigPath

Write-Host 'Descargando GoogleService-Info.plist...'
Save-ConfigFile -ConfigName "$($iosApp.name)/config" -OutputPath $iosConfigPath

Write-Host ''
Write-Host 'Firebase apps listas.'
Write-Host "Android app id: $($androidApp.appId)"
Write-Host "iOS app id: $($iosApp.appId)"
Write-Host "Archivo Android: $androidConfigPath"
Write-Host "Archivo iOS: $iosConfigPath"
