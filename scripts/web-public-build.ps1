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

$repoRootResolved = (Resolve-Path $repoRoot).Path
$buildDirs = @(
  (Join-Path $webPublic '.next'),
  (Join-Path $webPublic 'out')
)

foreach ($dir in $buildDirs) {
  if (-not (Test-Path $dir)) {
    continue
  }

  $resolved = (Resolve-Path $dir).Path
  if (-not $resolved.StartsWith($repoRootResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Ruta de build fuera del repo: $resolved"
  }

  Remove-Item -LiteralPath $resolved -Recurse -Force
}

$currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'Process')
[System.Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
[System.Environment]::SetEnvironmentVariable('Path', "$nodeDir;$currentPath", 'Process')

& $npm run build --prefix $webPublic
