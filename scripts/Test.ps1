#Requires -Version 7.2
param(
    [string[]]$PowerShellPaths = @((Get-Command pwsh -ErrorAction Stop).Source),
    [string]$HookPath,
    [string]$ReportPath
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $HookPath) { $HookPath = Join-Path $root 'artifacts/package/PwshUtf8Hook.dll' }
if (-not $ReportPath) { $ReportPath = Join-Path $root 'artifacts/test-results.json' }
$hook = (Resolve-Path -LiteralPath $HookPath).ProviderPath
$probe = (Resolve-Path -LiteralPath (Join-Path $root 'tests/RuntimeProbe/bin/Release/net6.0/RuntimeProbe.dll')).ProviderPath
$dotnet = (Get-Command dotnet -ErrorAction Stop).Source
$work = Join-Path $root ('work/test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$results = [Collections.Generic.List[object]]::new()
$userBefore = [Environment]::GetEnvironmentVariable('DOTNET_STARTUP_HOOKS','User')
$machineBefore = [Environment]::GetEnvironmentVariable('DOTNET_STARTUP_HOOKS','Machine')
$processBefore = $env:DOTNET_STARTUP_HOOKS

function Assert-Case([string]$Name, [bool]$Passed, $Details = $null) {
    $results.Add([pscustomobject]@{ Test=$Name; Passed=$Passed; Details=$Details })
    if (-not $Passed) { throw "FAILED: $Name" }
}

function Invoke-Probe([string]$Exe, [string[]]$Arguments, [string]$Dll, [string]$InputText = '') {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Exe
    $info.WorkingDirectory = $work
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $null = $info.Environment.Remove('DOTNET_STARTUP_HOOKS')
    if ($Dll) { $info.Environment['DOTNET_STARTUP_HOOKS'] = $Dll }
    $info.Environment['PWSH_UTF8_TEST_DOTNET'] = $dotnet
    $info.Environment['PWSH_UTF8_TEST_PROBE'] = $probe
    $info.Environment['PWSH_UTF8_TEST_RUNTIME'] = $runtimes[-1]
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::Start($info)
    $stdout = [IO.MemoryStream]::new()
    $stderr = [IO.MemoryStream]::new()
    try {
        $outTask = $child.StandardOutput.BaseStream.CopyToAsync($stdout)
        $errTask = $child.StandardError.BaseStream.CopyToAsync($stderr)
        $child.StandardInput.WriteLine($InputText)
        $child.StandardInput.Close()
        if (-not $child.WaitForExit(30000)) { $child.Kill($true); throw 'Child process timed out.' }
        $null = $outTask.GetAwaiter().GetResult()
        $null = $errTask.GetAwaiter().GetResult()
        $outBytes = $stdout.ToArray()
        $errBytes = $stderr.ToArray()
        $valid = $true
        try { $strict = [Text.UTF8Encoding]::new($false,$true); $outText = $strict.GetString($outBytes); $errText = $strict.GetString($errBytes) }
        catch { $valid = $false; $outText = [Text.Encoding]::UTF8.GetString($outBytes); $errText = [Text.Encoding]::UTF8.GetString($errBytes) }
        return [pscustomobject]@{ ExitCode=$child.ExitCode; Stdout=$outText; Stderr=$errText; ValidUtf8=$valid; HasBom=($outBytes.Length -ge 3 -and $outBytes[0] -eq 239 -and $outBytes[1] -eq 187 -and $outBytes[2] -eq 191) }
    } finally { $child.Dispose(); $stdout.Dispose(); $stderr.Dispose() }
}

$runtimes = @(& $dotnet --list-runtimes | ForEach-Object {
    if ($_ -match '^Microsoft\.NETCore\.App (\d+\.\d+\.\d+) ') { $Matches[1] }
} | Where-Object { [version]$_ -ge [version]'6.0.0' } | Sort-Object { [version]$_ })
if ($LASTEXITCODE -ne 0 -or $runtimes.Count -eq 0) { throw 'No supported .NET runtime found for the test probe.' }
$payload = @'
$line = [Console]::ReadLine()
$native = '管道中文😀' | & $env:PWSH_UTF8_TEST_DOTNET exec --fx-version $env:PWSH_UTF8_TEST_RUNTIME $env:PWSH_UTF8_TEST_PROBE echo
[pscustomobject]@{
    Version = $PSVersionTable.PSVersion.ToString()
    Runtime = [Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
    InputMatches = $line -ceq '输入中文😀'
    NativeMatches = $native -ceq '管道中文😀'
    Text = '输出中文😀'
    InputCP = [Console]::InputEncoding.CodePage
    OutputCP = [Console]::OutputEncoding.CodePage
    PipeCP = $OutputEncoding.CodePage
    Loaded = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'PwshUtf8Hook' }).Count -eq 1
} | ConvertTo-Json -Compress
[Console]::Error.Write('错误中文😀')
exit 23
'@
$script = Join-Path $work 'payload 中文.ps1'
[IO.File]::WriteAllText($script, $payload, [Text.UTF8Encoding]::new($false))

function Test-PowerShell([string]$Exe, [string]$Dll, [string]$Mode, [string]$Label) {
    $argument = switch ($Mode) {
        'Command' { $payload }
        'EncodedCommand' { [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload)) }
        'File' { $script }
    }
    $run = Invoke-Probe $Exe @('-NoLogo','-NoProfile','-NonInteractive',('-' + $Mode),$argument) $Dll '输入中文😀'
    $data = $run.Stdout | ConvertFrom-Json
    $passed = $run.ExitCode -eq 23 -and $run.ValidUtf8 -and -not $run.HasBom -and $data.Loaded -and $data.InputMatches -and $data.NativeMatches -and $data.Text -ceq '输出中文😀' -and $run.Stderr -ceq '错误中文😀' -and $data.InputCP -eq 65001 -and $data.OutputCP -eq 65001 -and $data.PipeCP -eq 65001
    Assert-Case "$Label PowerShell $($data.Version) -NoProfile -$Mode" $passed ([pscustomobject]@{ Runtime=$data.Runtime; InputCP=$data.InputCP; OutputCP=$data.OutputCP; PipeCP=$data.PipeCP; ExitCode=$run.ExitCode })
}

try {
    foreach ($executable in $PowerShellPaths) {
        $baselineScript = '[pscustomobject]@{ InputCP=[Console]::InputEncoding.CodePage; OutputCP=[Console]::OutputEncoding.CodePage; Loaded=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "PwshUtf8Hook" }).Count -gt 0 } | ConvertTo-Json -Compress'
        $baseline = Invoke-Probe $executable @('-NoProfile','-NonInteractive','-Command',$baselineScript) ''
        $baseData = $baseline.Stdout | ConvertFrom-Json
        Assert-Case 'Unhooked baseline starts without the hook' ($baseline.ExitCode -eq 0 -and -not $baseData.Loaded) $baseData
        foreach ($mode in @('Command','EncodedCommand','File')) { Test-PowerShell $executable $hook $mode 'Package DLL' }
    }
    foreach ($runtime in $runtimes) {
        $arguments = @('exec','--fx-version',$runtime,$probe)
        $before = Invoke-Probe $dotnet $arguments ''
        $after = Invoke-Probe $dotnet $arguments $hook
        $a = $before.Stdout | ConvertFrom-Json
        $b = $after.Stdout | ConvertFrom-Json
        Assert-Case "Other .NET $runtime application unchanged" ($before.ExitCode -eq 17 -and $after.ExitCode -eq 17 -and $before.Stderr -ceq $after.Stderr -and $a.InputCP -eq $b.InputCP -and $a.OutputCP -eq $b.OutputCP -and -not $a.HookLoaded -and $b.HookLoaded) $b
    }
    $ps51 = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $control = '[Console]::Write("IN="+[Console]::InputEncoding.CodePage+";OUT="+[Console]::OutputEncoding.CodePage+";PIPE="+$OutputEncoding.CodePage); exit 17'
    $a = Invoke-Probe $ps51 @('-NoProfile','-Command',$control) ''
    $b = Invoke-Probe $ps51 @('-NoProfile','-Command',$control) $hook
    Assert-Case 'Windows PowerShell 5.1 unchanged' ($a.ExitCode -eq 17 -and $b.ExitCode -eq 17 -and $a.Stdout -ceq $b.Stdout -and $a.Stderr -ceq $b.Stderr)

    $install = Join-Path $PSScriptRoot 'Install.ps1'
    $uninstall = Join-Path $PSScriptRoot 'Uninstall.ps1'
    $directory = Join-Path $work 'installed path 中文'
    [Environment]::SetEnvironmentVariable('DOTNET_STARTUP_HOOKS',[NullString]::Value,'Process')
    $null = & $install -DllPath $hook -InstallDirectory $directory -Scope Process -WhatIf
    Assert-Case 'Installer WhatIf has no filesystem/environment effects' (-not (Test-Path -LiteralPath $directory) -and -not $env:DOTNET_STARTUP_HOOKS)
    $installed = & $install -DllPath $hook -InstallDirectory $directory -Scope Process
    Assert-Case 'Install verifies copied DLL hash' ((Get-FileHash -LiteralPath $installed.Dll).Hash -ceq (Get-FileHash -LiteralPath $hook).Hash)
    $again = & $install -DllPath $hook -InstallDirectory $directory -Scope Process
    Assert-Case 'Install is idempotent' ($again.Dll -ceq $installed.Dll -and $env:DOTNET_STARTUP_HOOKS -ceq $installed.Dll)
    foreach ($executable in $PowerShellPaths) { Test-PowerShell $executable $installed.Dll 'Command' 'Installed DLL (space/Unicode path)' }
    $null = & $uninstall -InstallDirectory $directory -Scope Process
    Assert-Case 'Uninstall restores absent environment variable' ([Environment]::GetEnvironmentVariable('DOTNET_STARTUP_HOOKS','Process') -ceq $null)
    $prior = 'prior-observability-hook'
    [Environment]::SetEnvironmentVariable('DOTNET_STARTUP_HOOKS',$prior,'Process')
    $otherDirectory = Join-Path $work 'existing-hooks'
    $existing = & $install -DllPath $hook -InstallDirectory $otherDirectory -Scope Process
    Assert-Case 'Install preserves existing hook' ($env:DOTNET_STARTUP_HOOKS -ceq ($prior+';'+$existing.Dll))
    $null = & $uninstall -InstallDirectory $otherDirectory -Scope Process
    Assert-Case 'Uninstall restores exact prior value' ($env:DOTNET_STARTUP_HOOKS -ceq $prior)
    $existing = & $install -DllPath $hook -InstallDirectory $otherDirectory -Scope Process
    $env:DOTNET_STARTUP_HOOKS += ';later-observability-hook'
    $null = & $uninstall -InstallDirectory $otherDirectory -Scope Process
    Assert-Case 'Uninstall preserves hooks added later' ($env:DOTNET_STARTUP_HOOKS -ceq ($prior+';later-observability-hook'))
    $snapshot = $env:DOTNET_STARTUP_HOOKS
    $rejected = $false
    try { $null = & $install -DllPath $hook -InstallDirectory (Join-Path $env:LOCALAPPDATA 'PwshUtf8Hook-Test') -Scope Process } catch { $rejected = $true }
    Assert-Case 'Installer rejects the Store-invisible LocalAppData location' ($rejected -and $env:DOTNET_STARTUP_HOOKS -ceq $snapshot)
    $rejected = $false
    try { $null = & $install -DllPath $hook -InstallDirectory (Join-Path $work 'bad;path') -Scope Process } catch { $rejected = $true }
    Assert-Case 'Installer rejects a startup-hook separator in the path' ($rejected -and -not (Test-Path -LiteralPath (Join-Path $work 'bad;path')))
    $env:DOTNET_STARTUP_HOOKS = $hook
    $rejected = $false
    try { $null = & $install -DllPath $hook -InstallDirectory (Join-Path $work 'duplicate') -Scope Process } catch { $rejected = $true }
    Assert-Case 'Installer rejects duplicate hook assemblies' ($rejected -and $env:DOTNET_STARTUP_HOOKS -ceq $hook)
    Assert-Case 'User and machine settings unchanged' ([Environment]::GetEnvironmentVariable('DOTNET_STARTUP_HOOKS','User') -ceq $userBefore -and [Environment]::GetEnvironmentVariable('DOTNET_STARTUP_HOOKS','Machine') -ceq $machineBefore)
} finally {
    if ($null -eq $processBefore) { [Environment]::SetEnvironmentVariable('DOTNET_STARTUP_HOOKS',[NullString]::Value,'Process') }
    else { [Environment]::SetEnvironmentVariable('DOTNET_STARTUP_HOOKS',$processBefore,'Process') }
    $parent = Split-Path ([IO.Path]::GetFullPath($ReportPath)) -Parent
    $null = New-Item -ItemType Directory -Path $parent -Force
    $report = [pscustomobject]@{ CreatedAtUtc=[DateTime]::UtcNow.ToString('o'); DllSHA256=(Get-FileHash -LiteralPath $hook).Hash; Tests=$results }
    [IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 7), [Text.UTF8Encoding]::new($false))
}
$results | Select-Object Test,Passed | Format-Table -AutoSize
Write-Output "$($results.Count) checks passed. Report: $ReportPath"
