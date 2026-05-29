$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectId = 'fleteapp-8d8f7'
$siteId = 'fleteapp-public-8d8f7'

function Get-FirebaseCli {
  $command = Get-Command firebase -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  throw 'No se encontro el comando firebase en PowerShell. Si estas en el prompt > de Firebase/Firepit, ejecuta los comandos firebase manualmente ahi; no ejecutes powershell -File dentro de ese prompt.'
}

$firebase = Get-FirebaseCli

& $firebase hosting:sites:create $siteId --project $projectId
if ($LASTEXITCODE -ne 0) {
  Write-Warning 'Si el sitio ya existia, puedes continuar. Si no existia, copia el error y revisamos.'
}

& $firebase target:apply hosting public $siteId --project $projectId
