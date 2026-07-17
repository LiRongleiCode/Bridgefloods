[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$WindowsRoot = Split-Path -Parent $PSScriptRoot
$Source = Get-Content (Join-Path $WindowsRoot 'app\Program.cs') -Raw
$Launcher = Get-Content (Join-Path $WindowsRoot 'scripts\start-dream-skin.ps1') -Raw
$Injector = Get-Content (Join-Path $WindowsRoot 'scripts\injector.mjs') -Raw
$InjectorPath = Join-Path $WindowsRoot 'scripts\injector.mjs'
$ExePath = Join-Path $WindowsRoot 'DreamSkin.exe'

function Test-InjectorHttpTimeout {
  $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  $client = $null
  $process = $null
  try {
    $listener.Start()
    $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $acceptTask = $listener.AcceptTcpClientAsync()
    $node = (Get-Command node -ErrorAction Stop).Source
    $quotedInjector = '"' + $InjectorPath + '"'
    $process = Start-Process -FilePath $node -ArgumentList @(
      $quotedInjector, '--verify', '--port', "$port", '--timeout-ms', '1200'
    ) -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(8000)) {
      try { $process.Kill() } catch {}
      return $false
    }
    if ($acceptTask.IsCompleted) { $client = $acceptTask.Result }
    return $process.ExitCode -ne 0
  } finally {
    if ($client) { $client.Dispose() }
    $listener.Stop()
    if ($process) { $process.Dispose() }
  }
}

$InjectorHttpTimeoutWorks = Test-InjectorHttpTimeout
$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'verify-injector-timeouts.mjs')
$InjectorTimeoutBehaviorWorks = $LASTEXITCODE -eq 0
& $node (Join-Path $PSScriptRoot 'verify-injector-payloads.mjs')
$InjectorPayloadValidationWorks = $LASTEXITCODE -eq 0

$checks = [ordered]@{
  'apply handler is asynchronous' = $Source.Contains('ApplyThemeAsync') -and $Source.Contains('await Task.Run(() => RunPowerShell("start-dream-skin.ps1"))')
  'restore handler is asynchronous' = $Source.Contains('RestoreThemeAsync') -and $Source.Contains('await Task.Run(() => RunPowerShell("restore-dream-skin.ps1"))')
  'script output is drained concurrently' = $Source.Contains('ReadToEndAsync()') -and $Source.Contains('Task.WaitAll(outputTask, errorTask)')
  'script timeout exists' = $Source.Contains('ScriptTimeoutMilliseconds') -and $Source.Contains('Kill(entireProcessTree: true)')
  'launcher cleans failed injector' = $Launcher.Contains('Stop-Process -Id $daemon.Id') -and $Launcher.Contains('Remove-Item -LiteralPath $StatePath')
  'launcher only terminates official Codex processes' = $Launcher.Contains('Get-CodexProcesses $exe | ForEach-Object') -and -not $Launcher.Contains('Get-Process ChatGPT -ErrorAction SilentlyContinue | Stop-Process -Force')
  'launcher verifies CDP listener ownership' = $Launcher.Contains('Get-NetTCPConnection -State Listen') -and $Launcher.Contains('Test-ProcessBelongsToCodex $listenerPid $ExpectedExe')
  'launcher binds CDP to loopback' = $Launcher.Contains('--remote-debugging-address=127.0.0.1')
  'injector WebSocket open timeout exists' = $Injector.Contains('CDP WebSocket open timed out')
  'injector command timeout exists' = $Injector.Contains('CDP command timed out: ${method}')
  'injector HTTP discovery timeout exists' = $Injector.Contains('new AbortController()') -and $Injector.Contains('signal: controller.signal')
  'injector exits when CDP HTTP stalls' = $InjectorHttpTimeoutWorks
  'injector exits when WebSocket or CDP commands stall' = $InjectorTimeoutBehaviorWorks
  'injectors reject unsafe theme payloads and arguments' = $InjectorPayloadValidationWorks
  'standalone executable exists' = Test-Path -LiteralPath $ExePath
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
if ($failed.Count -gt 0) {
  throw ('DreamSkin regression checks failed: ' + (($failed | ForEach-Object Key) -join ', '))
}

$bytes = Get-Content -LiteralPath $ExePath -Encoding Byte -TotalCount 2
if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { throw 'DreamSkin.exe is not a Windows PE executable.' }
Write-Host ('DreamSkin app checks passed: {0}' -f ($checks.Keys -join ', '))
