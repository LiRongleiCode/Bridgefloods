[CmdletBinding()]
param([switch]$FrameworkDependent)

$ErrorActionPreference = 'Stop'
$WindowsRoot = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $WindowsRoot 'app\DreamSkin.csproj'
$PublishDir = Join-Path $WindowsRoot 'app\bin\Release\net7.0-windows\win-x64\publish'
$publishArgs = @(
  'publish', $Project,
  '-c', 'Release',
  '-r', 'win-x64',
  '--self-contained', $(if ($FrameworkDependent) { 'false' } else { 'true' }),
  '-p:PublishSingleFile=true',
  '-p:IncludeNativeLibrariesForSelfExtract=true',
  '-o', $PublishDir
)

& dotnet @publishArgs
if ($LASTEXITCODE -ne 0) { throw 'DreamSkin build failed.' }

$artifact = Join-Path $PublishDir 'DreamSkin.exe'
if (-not (Test-Path -LiteralPath $artifact)) { throw "Build succeeded but artifact was not found: $artifact" }
$target = Join-Path $WindowsRoot 'DreamSkin.exe'
Copy-Item -LiteralPath $artifact -Destination $target -Force
Write-Host "DreamSkin.exe created at $target"
