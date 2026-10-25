param()
$ErrorActionPreference = 'Stop'
$taskProject = $PSScriptRoot
$taskOutput = Join-Path $taskProject 'build'
$taskMinhook = Join-Path $taskProject 'vendor\minhook'
$taskVcvars = & (Join-Path $PSScriptRoot 'Find-Vcvars.ps1')
if (!(Test-Path -LiteralPath $taskVcvars)) { throw 'The x86 Visual Studio Build Tools were not found.' }
if (!(Test-Path -LiteralPath (Join-Path $taskMinhook 'include\MinHook.h'))) { throw 'The bundled MinHook source was not found.' }
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskSources = @(
  (Join-Path $taskProject 'zBoxBridge.cpp'),
  (Join-Path $taskMinhook 'src\buffer.c'),
  (Join-Path $taskMinhook 'src\hook.c'),
  (Join-Path $taskMinhook 'src\trampoline.c'),
  (Join-Path $taskMinhook 'src\hde\hde32.c')
)
$taskInputs = ($taskSources | ForEach-Object { '"' + $_ + '"' }) -join ' '
$taskCommand = 'call "' + $taskVcvars + '" x86 >nul && cl /nologo /LD /O2 /MT /EHsc /std:c++17 ' +
  '/I"' + (Join-Path $taskMinhook 'include') + '" /I"' + (Join-Path $taskMinhook 'src') + '" ' +
  $taskInputs + ' /link /DEF:"' + (Join-Path $taskProject 'zBoxBridge.def') +
  '" /OUT:"' + (Join-Path $taskOutput 'zBoxBridge.dll') + '" user32.lib kernel32.lib'
Push-Location -LiteralPath $taskOutput
try {
  & cmd.exe /d /s /c $taskCommand
  if ($LASTEXITCODE -ne 0) { throw "zBoxBridge build failed: $LASTEXITCODE" }
} finally { Pop-Location }
Get-FileHash -LiteralPath (Join-Path $taskOutput 'zBoxBridge.dll') -Algorithm SHA256
