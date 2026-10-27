$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskOutput = Join-Path $PSScriptRoot 'build'
$taskVcvars = & (Join-Path $taskRoot 'native\Find-Vcvars.ps1')
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskCommand = 'call "' + $taskVcvars + '" x86 >nul && cl /nologo /O2 /MT /EHsc /std:c++17 ' +
  '"' + (Join-Path $PSScriptRoot 'test_local_bank.cpp') + '" /Fe:"' +
  (Join-Path $taskOutput 'test_local_bank.exe') + '" bcrypt.lib advapi32.lib'
Push-Location -LiteralPath $taskOutput
try {
  & cmd.exe /d /s /c $taskCommand
  if ($LASTEXITCODE -ne 0) { throw 'Local IPC fixture compilation failed' }
  & (Join-Path $taskOutput 'test_local_bank.exe')
  if ($LASTEXITCODE -ne 0) { throw 'Local IPC fixture failed' }
} finally { Pop-Location }
