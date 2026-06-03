$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'app-build-web.ps1'
$projectId = 'fleteapp-8d8f7'

function Get-FirebaseCli {
  $command = Get-Command firebase -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $localToolsDir = Join-Path $repoRoot '.local-tools'
  if (Test-Path $localToolsDir) {
    $localFirebase = Get-ChildItem `
      -Path $localToolsDir `
      -Filter 'firebase.cmd' `
      -Recurse `
      -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -like '*\node-v*-win-x64\firebase.cmd' } |
      Select-Object -First 1

    if ($localFirebase) {
      return $localFirebase.FullName
    }
  }

  return $null
}

$firebase = Get-FirebaseCli

& $buildScript
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

if ($firebase) {
  & $firebase deploy --only hosting:app --project $projectId
  exit $LASTEXITCODE
}

Write-Host ''
Write-Host 'Build listo, pero Firebase CLI no esta disponible como comando de PowerShell.'
Write-Host 'Abre Firebase/Firepit desde PowerShell con:'
Write-Host ''
Write-Host '.\.local-tools\firebase-tools-instant-win.exe'
Write-Host ''
Write-Host 'Luego, en el prompt > de Firebase/Firepit, ejecuta:'
Write-Host ''
Write-Host "firebase deploy --only hosting:app --project $projectId"
