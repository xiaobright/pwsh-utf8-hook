#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallDirectory = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Documents\PwshUtf8Hook'),
    [ValidateSet('User','Process')][string]$Scope = 'User'
)
$ErrorActionPreference = 'Stop'
$name = 'DOTNET_STARTUP_HOOKS'
$statePath = Join-Path ([IO.Path]::GetFullPath($InstallDirectory)) ('state-' + $Scope.ToLowerInvariant() + '.json')
if (-not (Test-Path -LiteralPath $statePath)) { Write-Output 'No installation record; no settings changed.'; return }
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
$current = [Environment]::GetEnvironmentVariable($name, $Scope)
if ($current -ceq $state.InstalledValue) { $restore = $state.PreviousValue }
elseif ($current -ceq $state.PreviousValue) { Write-Output 'Already disabled; no settings changed.'; return }
else {
    # Preserve hooks added by another application after installation.
    $entries = @($current -split ';')
    if ($entries -notcontains $state.DllPath) { Write-Output 'This hook is no longer configured; no settings changed.'; return }
    $restore = (@($entries | Where-Object { $_ -ine $state.DllPath }) -join ';')
    if ([string]::IsNullOrEmpty($restore)) { $restore = $null }
}
if (-not $PSCmdlet.ShouldProcess($Scope, 'Remove PwshUtf8Hook from the startup-hook setting')) { return }
if ($null -eq $restore) {
    # PowerShell otherwise binds $null to an empty string; .NET 9+ preserves it.
    [Environment]::SetEnvironmentVariable($name, [NullString]::Value, $Scope)
} else { [Environment]::SetEnvironmentVariable($name, $restore, $Scope) }
if ([Environment]::GetEnvironmentVariable($name, $Scope) -cne $restore) { throw 'Environment restoration failed.' }
Write-Output 'Disabled. Restart applications. DLL versions and installation record were retained.'
