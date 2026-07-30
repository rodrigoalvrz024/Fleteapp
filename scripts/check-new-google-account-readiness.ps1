param(
  [string]$ProjectId = $env:PROJECT_ID
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) {
  $checks.Add([pscustomobject]@{
    Check = $Name
    Ok = $Ok
    Detail = $Detail
  })
}

Add-Check 'PROJECT_ID cargado' (-not [string]::IsNullOrWhiteSpace($ProjectId)) "PROJECT_ID=$ProjectId"
Add-Check 'PROJECT_ID no es el antiguo' ($ProjectId -ne 'fleteapp-8d8f7') 'Debe apuntar al proyecto nuevo.'
Add-Check 'API_BASE_URL cargada' (-not [string]::IsNullOrWhiteSpace($env:API_BASE_URL)) "API_BASE_URL=$env:API_BASE_URL"
Add-Check 'NEXT_PUBLIC_SITE_URL cargada' (-not [string]::IsNullOrWhiteSpace($env:NEXT_PUBLIC_SITE_URL)) "NEXT_PUBLIC_SITE_URL=$env:NEXT_PUBLIC_SITE_URL"
Add-Check 'FIREBASE_WEB_API_KEY cargada' (-not [string]::IsNullOrWhiteSpace($env:FIREBASE_WEB_API_KEY)) 'Necesaria para Firebase web.'
Add-Check 'FIREBASE_WEB_APP_ID cargada' (-not [string]::IsNullOrWhiteSpace($env:FIREBASE_WEB_APP_ID)) 'Necesaria para Firebase web.'

$androidConfig = Join-Path $repoRoot 'mobile\android\app\google-services.json'
if (Test-Path $androidConfig) {
  $json = Get-Content $androidConfig -Raw | ConvertFrom-Json
  $packages = @($json.client | ForEach-Object { $_.client_info.android_client_info.package_name })
  Add-Check 'google-services contiene cl.muvv.app' ($packages -contains 'cl.muvv.app') ($packages -join ', ')
} else {
  Add-Check 'google-services existe' $false $androidConfig
}

$iosConfig = Join-Path $repoRoot 'mobile\ios\Runner\GoogleService-Info.plist'
if (Test-Path $iosConfig) {
  $plist = Get-Content $iosConfig -Raw
  Add-Check 'GoogleService-Info tiene bundle cl.muvv.app' ($plist -match '<string>cl\.muvv\.app</string>') $iosConfig
} else {
  Add-Check 'GoogleService-Info existe' $false $iosConfig
}

$importantFiles = @(
  '.firebaserc',
  'web-public\src\app\seo.ts',
  'mobile\lib\firebase_options.dart',
  'mobile\lib\core\constants\api_constants.dart',
  'backend\.env.example',
  'scripts\app-build-web.ps1',
  'scripts\app-deploy.ps1',
  'scripts\web-public-deploy.ps1',
  'scripts\web-public-create-site.ps1'
) | ForEach-Object { Join-Path $repoRoot $_ }

$oldReferences = @()
foreach ($file in $importantFiles) {
  if (Test-Path $file) {
    $matches = Select-String -Path $file -Pattern 'fleteapp-8d8f7|591141449914|fleteapp-api|fleteapp-public' -SimpleMatch:$false
    foreach ($match in $matches) {
      $oldReferences += "$($match.Path):$($match.LineNumber)"
    }
  }
}

Add-Check 'Referencias antiguas criticas revisadas' ($oldReferences.Count -eq 0) (($oldReferences | Select-Object -First 12) -join '; ')

$checks | Format-Table -AutoSize

if ($checks | Where-Object { -not $_.Ok }) {
  exit 1
}
