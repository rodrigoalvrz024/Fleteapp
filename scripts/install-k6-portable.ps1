$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$version = if ([string]::IsNullOrWhiteSpace($env:K6_VERSION)) { '2.0.0' } else { $env:K6_VERSION }
$toolsDir = Join-Path $repoRoot '.local-tools\k6'
$zipPath = Join-Path $env:TEMP "k6-v$version-windows-amd64.zip"
$downloadUrl = "https://github.com/grafana/k6/releases/download/v$version/k6-v$version-windows-amd64.zip"

New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

Write-Host "Descargando k6 portable v$version..."
Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $zipPath

Write-Host 'Extrayendo k6...'
$extractDir = Join-Path $env:TEMP "k6-v$version"
if (Test-Path $extractDir) {
  Remove-Item -Recurse -Force -LiteralPath $extractDir
}
Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

$exe = Get-ChildItem -Path $extractDir -Filter k6.exe -Recurse | Select-Object -First 1
if (-not $exe) {
  throw 'No se encontro k6.exe dentro del zip descargado.'
}

Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $toolsDir 'k6.exe') -Force

Write-Host "k6 portable instalado en $toolsDir"
& (Join-Path $toolsDir 'k6.exe') version
