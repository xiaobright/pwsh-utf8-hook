#Requires -Version 7.4
param([Parameter(Mandatory)][string]$Version)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pin = @(Get-Content -LiteralPath (Join-Path $root 'tests/powershell-versions.json') -Raw | ConvertFrom-Json | Where-Object version -eq $Version)
if ($pin.Count -ne 1) { throw 'Version is not in the pinned compatibility manifest.' }
$directory = Join-Path $root ('work/portable-' + $Version)
$archive = $directory + '.zip'
$null = New-Item -ItemType Directory -Path (Split-Path $directory -Parent) -Force
$releaseText = & gh api ('repos/PowerShell/PowerShell/releases/tags/v' + $Version)
if ($LASTEXITCODE -ne 0) { throw 'GitHub release lookup failed.' }
$release = $releaseText | ConvertFrom-Json
$asset = @($release.assets | Where-Object name -eq ('PowerShell-' + $Version + '-win-x64.zip'))
if ($asset.Count -ne 1) { throw 'Expected Windows x64 ZIP asset is missing.' }
if (-not (Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive).Hash -ine $pin[0].sha256) {
    # PowerShell 7.4+ preserves native stdout bytes when redirecting to a file.
    & gh api ('repos/PowerShell/PowerShell/releases/assets/' + $asset[0].id) -H 'Accept: application/octet-stream' > $archive
    if ($LASTEXITCODE -ne 0) { throw 'PowerShell download failed.' }
}
if ((Get-FileHash -LiteralPath $archive).Hash -ine $pin[0].sha256) { throw 'Downloaded ZIP does not match the pinned SHA-256.' }
if (-not (Test-Path -LiteralPath (Join-Path $directory 'pwsh.exe'))) { Expand-Archive -LiteralPath $archive -DestinationPath $directory }
Write-Output (Join-Path $directory 'pwsh.exe')
