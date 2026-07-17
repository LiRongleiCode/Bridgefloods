[CmdletBinding()]
param(
  [int]$Port = 9335,
  [string]$ScreenshotPath
)

$ErrorActionPreference = 'Stop'
$node = (Get-Command node -ErrorAction Stop).Source
$injector = Join-Path $PSScriptRoot 'injector.mjs'
$themeDir = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\theme'
$arguments = @($injector, '--verify', '--port', "$Port")
if (Test-Path (Join-Path $themeDir 'theme.json')) { $arguments += @('--theme-dir', $themeDir) }
if ($ScreenshotPath) { $arguments += @('--screenshot', $ScreenshotPath) }
& $node @arguments
exit $LASTEXITCODE
