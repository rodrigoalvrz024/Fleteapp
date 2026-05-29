$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$nodeDir = Join-Path $repoRoot '.local-tools\node-v24.16.0-win-x64'
$npm = Join-Path $nodeDir 'npm.cmd'
$webPublic = Join-Path $repoRoot 'web-public'

if (-not (Test-Path $npm)) {
  throw "No se encontro npm portable en $npm. Ejecuta primero la instalacion de dependencias."
}

if (-not (Test-Path $webPublic)) {
  throw "No se encontro web-public en $webPublic."
}

$currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'Process')
[System.Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
[System.Environment]::SetEnvironmentVariable('Path', "$nodeDir;$currentPath", 'Process')

& $npm run build --prefix $webPublic
