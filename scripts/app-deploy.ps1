$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'app-build-web.ps1'
$projectId = 'fleteapp-8d8f7'

function Get-FirebaseCli {
  $command = Get-Command firebase -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  throw 'No se encontro el comando firebase en PowerShell. Si estas en el prompt > de Firebase/Firepit, ejecuta firebase deploy manualmente ahi; no ejecutes powershell -File dentro de ese prompt.'
}

$firebase = Get-FirebaseCli

& $buildScript
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& $firebase deploy --only hosting:app --project $projectId
