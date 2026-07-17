[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$RestartExisting,
  [string]$ProfilePath,
  [string]$ThemeDir,
  [switch]$ForegroundInjector
)

$ErrorActionPreference = 'Stop'
$SkillRoot = Split-Path -Parent $PSScriptRoot
$Injector = Join-Path $PSScriptRoot 'injector.mjs'
$StateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$StatePath = Join-Path $StateRoot 'state.json'
$StdoutPath = Join-Path $StateRoot 'injector.log'
$StderrPath = Join-Path $StateRoot 'injector-error.log'
$DefaultThemeDir = Join-Path $StateRoot 'theme'
if (-not $ThemeDir) { $ThemeDir = if (Test-Path (Join-Path $DefaultThemeDir 'theme.json')) { $DefaultThemeDir } else { Join-Path $SkillRoot 'assets' } }
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

function Get-ProcessIdentity([int]$ProcessId) {
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
  if (-not $process) { return $null }
  [pscustomobject]@{
    pid = [int]$process.ProcessId
    executablePath = [string]$process.ExecutablePath
    commandLine = [string]$process.CommandLine
    createdAt = if ($process.CreationDate) { ([System.Management.ManagementDateTimeConverter]::ToDateTime($process.CreationDate)).ToUniversalTime().ToString('o') } else { '' }
  }
}

function Test-ProcessBelongsToCodex([int]$ProcessId, [string]$ExpectedExe) {
  $expectedPath = [IO.Path]::GetFullPath($ExpectedExe)
  $current = $ProcessId
  for ($depth = 0; $depth -lt 32 -and $current -gt 1; $depth++) {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $current" -ErrorAction SilentlyContinue
    if (-not $process) { return $false }
    if ($process.ExecutablePath) {
      try {
        if ([IO.Path]::GetFullPath([string]$process.ExecutablePath) -ieq $expectedPath) { return $true }
      } catch {}
    }
    $parent = [int]$process.ParentProcessId
    if ($parent -le 1 -or $parent -eq $current) { break }
    $current = $parent
  }
  return $false
}

function Get-CodexProcesses([string]$ExpectedExe) {
  $expectedPath = [IO.Path]::GetFullPath($ExpectedExe)
  @(
    Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue |
      Where-Object {
        if (-not $_.ExecutablePath) { return $false }
        try { return [IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq $expectedPath } catch { return $false }
      }
  )
}

function Get-ListenerProcessIds([int]$CandidatePort) {
  try {
    @(
      Get-NetTCPConnection -State Listen -LocalPort $CandidatePort -ErrorAction Stop |
        Select-Object -ExpandProperty OwningProcess -Unique
    )
  } catch {
    @()
  }
}

function Stop-RecordedInjector($State) {
  if (-not $State.injectorPid) { return }
  $identity = Get-ProcessIdentity ([int]$State.injectorPid)
  if (-not $identity) { return }
  $expectedNode = [IO.Path]::GetFullPath($node)
  $pathMatches = $identity.executablePath -and ([IO.Path]::GetFullPath($identity.executablePath) -ieq $expectedNode)
  $commandMatches = $identity.commandLine -and $identity.commandLine -like "*$Injector*--watch*"
  $startMatches = (-not $State.createdAt) -or ([datetime]$identity.createdAt -eq [datetime]$State.createdAt)
  if ($pathMatches -and $commandMatches -and $startMatches) {
    Stop-Process -Id $identity.pid -Force -ErrorAction SilentlyContinue
  }
}

function Test-CodexDebugPort([int]$CandidatePort, [string]$ExpectedExe) {
  $listeners = @(Get-ListenerProcessIds $CandidatePort)
  if ($listeners.Count -eq 0) { return $false }
  foreach ($listenerPid in $listeners) {
    if (-not (Test-ProcessBelongsToCodex $listenerPid $ExpectedExe)) { return $false }
  }
  try {
    $targets = Invoke-RestMethod "http://127.0.0.1:$CandidatePort/json/list" -TimeoutSec 1
    return [bool]($targets | Where-Object { $_.type -eq 'page' -and $_.url -like 'app://*' })
  } catch {
    return $false
  }
}

$node = (Get-Command node -ErrorAction Stop).Source
$package = Get-AppxPackage OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) { throw 'The OpenAI.Codex Store package is not installed.' }
$exe = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "Codex executable not found: $exe" }

$debugReady = Test-CodexDebugPort $Port $exe
$codexProcesses = @(Get-CodexProcesses $exe)
$mainProcesses = @(
  $codexProcesses | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue } |
    Where-Object { $_.MainWindowHandle -ne 0 }
)

if (-not $debugReady -and -not $ProfilePath -and $mainProcesses.Count -gt 0) {
  if (-not $RestartExisting) {
    throw "Codex is already running without dream-skin debugging on port $Port. Close Codex or rerun with -RestartExisting."
  }
  foreach ($process in $mainProcesses) { [void]$process.CloseMainWindow() }
  Start-Sleep -Seconds 2
  Get-CodexProcesses $exe | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 600
}

if (-not (Test-CodexDebugPort $Port $exe)) {
  $arguments = @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port")
  if ($ProfilePath) {
    New-Item -ItemType Directory -Force -Path $ProfilePath | Out-Null
    $arguments += "--user-data-dir=$ProfilePath"
  }
  Start-Process -FilePath $exe -ArgumentList $arguments
}

$deadline = (Get-Date).AddSeconds(30)
while (-not (Test-CodexDebugPort $Port $exe)) {
  if ((Get-Date) -ge $deadline) { throw "Codex did not expose CDP on port $Port within 30 seconds." }
  Start-Sleep -Milliseconds 400
}

if (Test-Path -LiteralPath $StatePath) {
  try {
    $old = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    Stop-RecordedInjector $old
  } catch {}
}

if ($ForegroundInjector) {
  & $node $Injector --watch --port $Port --theme-dir $ThemeDir
  exit $LASTEXITCODE
}

$injectorArgs = @($Injector, '--watch', '--port', "$Port", '--theme-dir', $ThemeDir)
$daemon = Start-Process -FilePath $node -ArgumentList $injectorArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
$identity = Get-ProcessIdentity $daemon.Id
@{
  port = $Port
  injectorPid = $daemon.Id
  startedAt = (Get-Date).ToUniversalTime().ToString('o')
  createdAt = $identity.createdAt
  executablePath = $identity.executablePath
  commandLine = $identity.commandLine
  injectorPath = $Injector
  nodePath = $node
  themeDir = $ThemeDir
  skillRoot = $SkillRoot
  profilePath = $ProfilePath
} | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding utf8

$verified = $false
for ($attempt = 0; $attempt -lt 45; $attempt++) {
  Start-Sleep -Milliseconds 700
  & $node $Injector --verify --port $Port --theme-dir $ThemeDir *> $null
  if ($LASTEXITCODE -eq 0) { $verified = $true; break }
}
if (-not $verified) {
  try {
    if ($daemon -and -not $daemon.HasExited) { Stop-Process -Id $daemon.Id -Force -ErrorAction SilentlyContinue }
  } catch {}
  Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
  throw 'Dream skin launched but verification failed. See injector logs.'
}
Write-Host ('Codex Dream Skin is active on port {0}.' -f $Port)
