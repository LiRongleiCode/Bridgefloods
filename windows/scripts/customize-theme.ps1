[CmdletBinding()]
param([int]$Port = 9335)

$ErrorActionPreference = 'Stop'
$StateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$ThemeDir = Join-Path $StateRoot 'theme'
New-Item -ItemType Directory -Force -Path $ThemeDir | Out-Null

Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = 'Theme images (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp'
$dialog.Title = 'Choose a Codex Dream Skin image'
$dialog.Multiselect = $false
if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
  Write-Host 'Image selection cancelled.'
  exit 0
}

$source = Get-Item -LiteralPath $dialog.FileName
if ($source.Length -lt 1 -or $source.Length -gt 16MB) {
  throw 'The image must be non-empty and no larger than 16 MB.'
}
$extension = $source.Extension.ToLowerInvariant()
if ($extension -notin @('.png', '.jpg', '.jpeg', '.webp')) {
  throw "Unsupported image format: $extension"
}

$destination = Join-Path $ThemeDir ("background" + $extension)
Copy-Item -LiteralPath $source.FullName -Destination $destination -Force
$theme = [ordered]@{
  schemaVersion = 1
  id = 'custom'
  name = 'My Dream Skin'
  brandSubtitle = 'CUSTOM IMAGE'
  style = 'adaptive'
  image = [IO.Path]::GetFileName($destination)
  promoTitle = 'My Dream Skin'
  promoSub = 'CUSTOM IMAGE'
}
$temporary = Join-Path $ThemeDir 'theme.json.tmp'
$theme | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporary -Encoding utf8
Move-Item -LiteralPath $temporary -Destination (Join-Path $ThemeDir 'theme.json') -Force

$start = Join-Path $PSScriptRoot 'start-dream-skin.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $start -Port $Port -ThemeDir $ThemeDir
if ($LASTEXITCODE -ne 0) {
  throw 'Image was saved, but Codex did not expose a verified CDP endpoint. Start Dream Skin with -RestartExisting first.'
}
Write-Host "Theme applied: $($source.Name)"
