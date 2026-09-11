param(
  [Parameter(Mandatory = $true)][string]$GitleaksPath,
  [ValidateSet('WorkingTree', 'Backend', 'History')][string]$Scope = 'WorkingTree'
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tool = (Resolve-Path -LiteralPath $GitleaksPath).Path
$auditRoot = Join-Path $root '.local-tools\secret-audit'
$run = Join-Path $auditRoot ('scan-' + [Guid]::NewGuid().ToString('N'))
$snapshot = Join-Path $run 'snapshot'
$rawReport = Join-Path $run 'gitleaks-redacted.json'
$config = Join-Path $run 'rules.toml'
$exitCode = 2
New-Item -ItemType Directory -Path $run | Out-Null

function Get-RepoFiles([string[]]$GitArguments) {
  $items = @(& git -C $root -c core.quotepath=false ls-files @GitArguments)
  if ($LASTEXITCODE -ne 0) { throw 'No se pudo enumerar el contenido del repositorio.' }
  return $items
}

try {
  # Explicit defaults, no repository allowlists, inline exceptions or baselines.
  "[extend]`nuseDefault = true" | Set-Content -LiteralPath $config -Encoding ascii
  $arguments = @('--config', $config, '--gitleaks-ignore-path', (Join-Path $run 'no-ignore-file'),
    '--ignore-gitleaks-allow', '--redact=100', '--report-format', 'json',
    '--report-path', $rawReport, '--no-banner', '--no-color', '--log-level', 'warn', '--timeout', '180')
  $files = @()
  if ($Scope -eq 'History') {
    & $tool git $root '--log-opts=--all' @arguments
    $exitCode = $LASTEXITCODE
  } else {
    if ($Scope -eq 'Backend') {
      $files = Get-RepoFiles -GitArguments @('--cached', '--others', '--exclude-standard', '--', 'backend', 'scripts', 'docs', '.github')
    } else {
      $files = @(Get-RepoFiles -GitArguments @('--cached')) +
        @(Get-RepoFiles -GitArguments @('--others', '--exclude-standard', '--', 'backend', 'scripts', 'docs', '.github'))
    }
    $files = @($files | Sort-Object -Unique)
    New-Item -ItemType Directory -Path $snapshot | Out-Null
    $copied = @()
    foreach ($relative in $files) {
      $source = [IO.Path]::GetFullPath((Join-Path $root $relative))
      if (-not $source.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Ruta fuera del repositorio; escaneo rechazado.'
      }
      if (-not (Test-Path -LiteralPath $source)) { continue } # Tracked deletion.
      $item = Get-Item -LiteralPath $source -Force
      if ($item.PSIsContainer) { throw 'Submodulo o directorio inesperado; revisar alcance.' }
      $parent = $item
      while ($parent.FullName -ne $root) {
        if (($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          throw 'Enlace o junction encontrado; no se seguira fuera del alcance.'
        }
        $parent = Get-Item -LiteralPath (Split-Path -Parent $parent.FullName) -Force
      }
      $destination = Join-Path $snapshot $relative
      New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
      Copy-Item -LiteralPath $source -Destination $destination
      $copied += $relative
    }
    $copied | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'files.json') -Encoding utf8
    & $tool dir $snapshot @arguments
    $exitCode = $LASTEXITCODE
  }
  if ($exitCode -notin @(0, 1) -or -not (Test-Path -LiteralPath $rawReport)) {
    throw 'Escaneo incompleto; no debe interpretarse como aprobado.'
  }
  $findings = @(Get-Content -LiteralPath $rawReport -Raw | ConvertFrom-Json)
  $metadata = @($findings | ForEach-Object {
    $file = $_.File
    $prefix = $snapshot.Replace('\', '/') + '/'
    if ($file.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $file = $file.Substring($prefix.Length) }
    [ordered]@{ RuleID=$_.RuleID; File=$file; StartLine=$_.StartLine; EndLine=$_.EndLine; Commit=$_.Commit }
  })
  $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run 'findings-metadata.json') -Encoding utf8
  $summary = [ordered]@{
    scope = $Scope
    head = (& git -C $root rev-parse HEAD)
    tool_version = (& $tool version)
    tool_sha256 = (Get-FileHash -LiteralPath $tool -Algorithm SHA256).Hash
    utc = [DateTime]::UtcNow.ToString('o')
    findings = $findings.Count
    copied_files = if ($Scope -eq 'History') { $null } else { $copied.Count }
    exit_code = $exitCode
    secrets_redacted = $true
    report_directory = $run
  }
  $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'summary.json') -Encoding utf8
  $summary | ConvertTo-Json
} finally {
  if (Test-Path -LiteralPath $snapshot) {
    $resolved = (Resolve-Path -LiteralPath $snapshot).Path
    $expected = [IO.Path]::GetFullPath((Join-Path $run 'snapshot'))
    if ($resolved -ne $expected -or
        -not $resolved.StartsWith([IO.Path]::GetFullPath($auditRoot) + '\', [StringComparison]::OrdinalIgnoreCase) -or
        ((Get-Item -LiteralPath $resolved -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw 'Ruta de limpieza inesperada; no se eliminara.'
    }
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
      try {
        Remove-Item -LiteralPath $resolved -Recurse -Force
        break
      } catch {
        if ($attempt -eq 4) { throw }
        Start-Sleep -Milliseconds (250 * ($attempt + 1))
      }
    }
  }
}
exit $exitCode
