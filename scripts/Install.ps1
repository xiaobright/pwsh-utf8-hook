#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DllPath,
    [string]$InstallDirectory = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Documents\PwshUtf8Hook'),
    [ValidateSet('User','Process')][string]$Scope = 'User'
)
$ErrorActionPreference = 'Stop'
$name = 'DOTNET_STARTUP_HOOKS'
if (-not $DllPath) {
    $DllPath = Join-Path $PSScriptRoot 'PwshUtf8Hook.dll'
    if (-not (Test-Path -LiteralPath $DllPath)) { $DllPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/package/PwshUtf8Hook.dll' }
}
$source = (Resolve-Path -LiteralPath $DllPath).ProviderPath
$directory = [IO.Path]::GetFullPath($InstallDirectory)
if ($directory.Contains(';')) { throw 'The installation path cannot contain a semicolon (startup-hook list separator).' }
$local = [Environment]::GetFolderPath('LocalApplicationData').TrimEnd('\')
if ($local -and ($directory -ieq $local -or $directory.StartsWith($local + '\', [StringComparison]::OrdinalIgnoreCase))) {
    throw 'Choose a directory outside LocalAppData; Store PowerShell may not be able to see this path.'
}
$hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$destination = Join-Path $directory ('versions\' + $hash.ToLowerInvariant() + '\PwshUtf8Hook.dll')
$statePath = Join-Path $directory ('state-' + $Scope.ToLowerInvariant() + '.json')
$before = [Environment]::GetEnvironmentVariable($name, $Scope)
$machine = [Environment]::GetEnvironmentVariable($name, 'Machine')
if (Test-Path -LiteralPath $statePath) {
    $old = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($old.InstalledValue -ceq $before) { $previous = $old.PreviousValue }
    elseif ($old.PreviousValue -ceq $before) { $previous = $before }
    else { throw 'The startup-hook setting changed after installation. Uninstall this hook before installing again.' }
} else { $previous = $before }
$base = if ($Scope -eq 'User' -and [string]::IsNullOrEmpty($previous)) { $machine } else { $previous }
foreach ($entry in @($base -split ';')) {
    if ($entry -and [IO.Path]::GetFileName($entry) -ieq 'PwshUtf8Hook.dll') {
        throw 'Another PwshUtf8Hook installation is already configured. Disable that installation first to avoid loading two copies.'
    }
}
$value = if ([string]::IsNullOrEmpty($base)) { $destination } else { $base + ';' + $destination }
if (-not $PSCmdlet.ShouldProcess($destination, "Install and configure $Scope startup hook")) { return }
$null = New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force
if (Test-Path -LiteralPath $destination) {
    if ((Get-FileHash -LiteralPath $destination).Hash -cne $hash) { throw 'Existing version directory has unexpected DLL contents.' }
} else { Copy-Item -LiteralPath $source -Destination $destination }
if ((Get-FileHash -LiteralPath $destination).Hash -cne $hash) { throw 'Copied DLL hash mismatch.' }
$uninstaller = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1')).ProviderPath
$installedUninstaller = Join-Path $directory 'Uninstall.ps1'
if ($uninstaller -ine $installedUninstaller) { Copy-Item -LiteralPath $uninstaller -Destination $installedUninstaller -Force }
$state = [pscustomobject]@{ Scope=$Scope; PreviousValue=$previous; InstalledValue=$value; DllPath=$destination; SHA256=$hash }
[IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
[Environment]::SetEnvironmentVariable($name, $value, $Scope)
if ([Environment]::GetEnvironmentVariable($name, $Scope) -cne $value) { throw 'Environment verification failed.' }
[pscustomobject]@{ Installed=$true; Scope=$Scope; Dll=$destination; RestartApplications=($Scope -eq 'User') }
