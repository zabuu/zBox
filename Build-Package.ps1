[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if (!$OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot 'dist' }
$taskVersion = ((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'zBox.toc') | Where-Object { $_ -match '^## Version:' }) -replace '^## Version:\s*','').Trim()
if ($taskVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid addon version in zBox.toc.' }
$taskFiles = @(& git -C $PSScriptRoot ls-files)
if ($LASTEXITCODE -ne 0 -or !$taskFiles.Count) { throw 'Build from a Git checkout with tracked files.' }
if (!($taskFiles -contains 'bin/zBoxBridge.dll')) { throw 'The prebuilt bridge must be tracked in the repository.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$taskOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path
$taskStage = [IO.Path]::GetFullPath((Join-Path $taskOutput ('stage-' + [guid]::NewGuid().ToString('N'))))
$taskRoot = Join-Path $taskStage 'zBox'
$taskArchive = Join-Path $taskOutput ("zBox-$taskVersion.zip")
try {
  foreach ($taskRelative in $taskFiles) {
    if ($taskRelative -match '^\.github/' -or $taskRelative -in @('.gitignore','.gitattributes')) { continue }
    $taskSource = Join-Path $PSScriptRoot $taskRelative
    $taskTarget = Join-Path $taskRoot $taskRelative
    New-Item -ItemType Directory -Path (Split-Path -Parent $taskTarget) -Force | Out-Null
    Copy-Item -LiteralPath $taskSource -Destination $taskTarget
  }
  Compress-Archive -LiteralPath $taskRoot -DestinationPath $taskArchive -Force
  $taskHash = (Get-FileHash -LiteralPath $taskArchive -Algorithm SHA256).Hash.ToLowerInvariant()
  [IO.File]::WriteAllText(($taskArchive + '.sha256'), ($taskHash + '  ' + (Split-Path -Leaf $taskArchive) + "`n"), [Text.Encoding]::ASCII)
  Write-Output $taskArchive
  Write-Output "SHA-256 $taskHash"
} finally {
  $taskPrefix = $taskOutput.TrimEnd('\') + '\'
  if (!$taskStage.StartsWith($taskPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Staging cleanup path is outside the output directory.' }
  if (Test-Path -LiteralPath $taskStage) { Remove-Item -LiteralPath $taskStage -Recurse -Force }
}
