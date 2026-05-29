$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'web-public-build.ps1'
$projectId = 'fleteapp-8d8f7'

function Get-FirebaseCli {
  $command = Get-Command firebase -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  return $null
}

$firebase = Get-FirebaseCli

& $buildScript
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

if ($firebase) {
  & $firebase deploy --only hosting:public --project $projectId
  exit $LASTEXITCODE
}

Write-Host ''
Write-Host 'Build listo, pero Firebase CLI no esta disponible como comando de PowerShell.'
Write-Host 'Ahora abre o vuelve al prompt > de Firebase/Firepit y ejecuta:'
Write-Host ''
Write-Host "firebase deploy --only hosting:public --project $projectId"
