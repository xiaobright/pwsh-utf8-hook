#Requires -Version 7.2
param([switch]$Package)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
foreach ($project in @('src/PwshUtf8Hook/PwshUtf8Hook.csproj', 'tests/RuntimeProbe/RuntimeProbe.csproj')) {
    & dotnet build (Join-Path $root $project) -c Release --nologo -p:ContinuousIntegrationBuild=true
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $project" }
}
$directory = Join-Path $root 'artifacts/package'
$null = New-Item -ItemType Directory -Path $directory -Force
Copy-Item -LiteralPath (Join-Path $root 'src/PwshUtf8Hook/bin/Release/netstandard2.0/PwshUtf8Hook.dll') -Destination $directory -Force
foreach ($file in @('Install.ps1','Uninstall.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $directory -Force }
foreach ($file in @('README.md','README.zh-CN.md','LICENSE')) { Copy-Item -LiteralPath (Join-Path $root $file) -Destination $directory -Force }
$null = New-Item -ItemType Directory -Path (Join-Path $directory 'docs') -Force
Copy-Item -LiteralPath (Join-Path $root 'docs/compatibility.md') -Destination (Join-Path $directory 'docs/compatibility.md') -Force
$hash = (Get-FileHash -LiteralPath (Join-Path $directory 'PwshUtf8Hook.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $directory 'SHA256SUMS.txt'), ($hash + '  PwshUtf8Hook.dll' + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
if ($Package) {
    $archive = Join-Path $root 'artifacts/pwsh-utf8-hook-1.0.0.zip'
    Compress-Archive -Path (Join-Path $directory '*') -DestinationPath $archive -Force
    $archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $root 'artifacts/SHA256SUMS.txt'), ($archiveHash + '  pwsh-utf8-hook-1.0.0.zip' + [Environment]::NewLine + $hash + '  PwshUtf8Hook.dll' + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}
Write-Output "DLL SHA-256: $hash"
