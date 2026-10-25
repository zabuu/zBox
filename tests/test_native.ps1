$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskOutput = Join-Path $PSScriptRoot 'build'
$taskVcvars = & (Join-Path $taskRoot 'native\Find-Vcvars.ps1')
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskCommand = 'call "' + $taskVcvars + '" x86 >nul && cl /nologo /O2 /MT /EHsc ' +
  '"' + (Join-Path $PSScriptRoot 'test_scoped_native.cpp') + '" /Fe:"' +
  (Join-Path $taskOutput 'test_scoped_native.exe') + '"'
Push-Location -LiteralPath $taskOutput
try {
  & cmd.exe /d /s /c $taskCommand
  if ($LASTEXITCODE -ne 0) { throw 'Native fixture compilation failed' }
  & (Join-Path $taskOutput 'test_scoped_native.exe') (Join-Path $taskRoot 'native\build\zBoxBridge.dll')
  if ($LASTEXITCODE -ne 0) { throw 'Native fixture failed' }
} finally { Pop-Location }
