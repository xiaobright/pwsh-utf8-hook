#Requires -Version 7.2
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$work = Join-Path $root ('work/ps51-research-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$results = [Collections.Generic.List[object]]::new()
$settingsBefore = @{}
foreach ($scope in @('User', 'Machine')) {
    foreach ($name in @('APPDOMAIN_MANAGER_ASM', 'APPDOMAIN_MANAGER_TYPE', 'DOTNET_STARTUP_HOOKS')) {
        $settingsBefore["$scope/$name"] = [Environment]::GetEnvironmentVariable($name, $scope)
    }
}
if (-not $SkipBuild) {
    foreach ($project in @('Ps51Utf8Research', 'FrameworkProbe')) {
        & dotnet build (Join-Path $PSScriptRoot "$project/$project.csproj") -c Release --nologo -v minimal
        if ($LASTEXITCODE -ne 0) { throw "Build failed: $project" }
    }
}
$dll = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'Ps51Utf8Research/bin/Release/net472/Ps51Utf8Research.dll')).Path
$probeSource = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'FrameworkProbe/bin/Release/net472/FrameworkProbe.exe')).Path
$nativeDir = Join-Path $work 'native-echo'
$null = New-Item -ItemType Directory -Path $nativeDir
Copy-Item -LiteralPath $probeSource -Destination $nativeDir
Copy-Item -LiteralPath $dll -Destination $nativeDir
$probe = Join-Path $nativeDir 'FrameworkProbe.exe'
$assembly = [Reflection.AssemblyName]::GetAssemblyName($dll).FullName
$manager = 'Ps51Utf8Research.DomainManager'
$hookEnvironment = @{ APPDOMAIN_MANAGER_ASM=$assembly; APPDOMAIN_MANAGER_TYPE=$manager }
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)

function Invoke-Child([string]$Exe, [string[]]$Arguments, [hashtable]$Environment = @{}, [string]$InputText = '') {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Exe
    $info.WorkingDirectory = $work
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($name in @('APPDOMAIN_MANAGER_ASM', 'APPDOMAIN_MANAGER_TYPE', 'DOTNET_STARTUP_HOOKS', 'PS51_UTF8_RESEARCH_CONSOLE_ONLY')) {
        $null = $info.Environment.Remove($name)
    }
    $info.Environment['PS51_UTF8_RESEARCH_PROBE'] = $probe
    foreach ($key in $Environment.Keys) { $info.Environment[$key] = $Environment[$key] }
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::Start($info)
    $out = [IO.MemoryStream]::new()
    $err = [IO.MemoryStream]::new()
    try {
        $outTask = $child.StandardOutput.BaseStream.CopyToAsync($out)
        $errTask = $child.StandardError.BaseStream.CopyToAsync($err)
        if ($InputText) { $child.StandardInput.WriteLine($InputText) }
        $child.StandardInput.Close()
        if (-not $child.WaitForExit(15000)) { $child.Kill($true); throw "Child timed out: $Exe" }
        $null = $outTask.GetAwaiter().GetResult()
        $null = $errTask.GetAwaiter().GetResult()
        $outBytes = $out.ToArray()
        $errBytes = $err.ToArray()
        $validUtf8 = $true
        try { $stdout = $strictUtf8.GetString($outBytes); $stderr = $strictUtf8.GetString($errBytes) }
        catch { $validUtf8 = $false; $stdout = [Text.Encoding]::UTF8.GetString($outBytes); $stderr = [Text.Encoding]::UTF8.GetString($errBytes) }
        [pscustomobject]@{ ExitCode=$child.ExitCode; Stdout=$stdout; Stderr=$stderr; ValidUtf8=$validUtf8; StdoutBase64=[Convert]::ToBase64String($outBytes); StderrBase64=[Convert]::ToBase64String($errBytes); HasBom=($outBytes.Length -ge 3 -and $outBytes[0] -eq 239 -and $outBytes[1] -eq 187 -and $outBytes[2] -eq 191) }
    } finally { $child.Dispose(); $out.Dispose(); $err.Dispose() }
}
function Record([string]$Name, [bool]$Passed, $Data) {
    $results.Add([pscustomobject]@{ Name=$Name; Passed=$Passed; Data=$Data })
    Write-Output "$Name : $Passed"
    if (-not $Passed) { throw "FAILED: $Name`n$($Data | ConvertTo-Json -Depth 8)" }
}
$simple = @'
$ProgressPreference='SilentlyContinue'
[pscustomobject]@{Version=$PSVersionTable.PSVersion.ToString();Bits=([IntPtr]::Size*8);InputCP=[Console]::InputEncoding.CodePage;OutputCP=[Console]::OutputEncoding.CodePage;PipeCP=$OutputEncoding.CodePage;DefaultCP=[Text.Encoding]::Default.CodePage;Hook=[AppDomain]::CurrentDomain.GetData('Ps51Utf8Research.Status')} | ConvertTo-Json -Compress
'@
$payload = @'
$ProgressPreference='SilentlyContinue'
$line = [Console]::ReadLine()
$native = '管道中文😀' | & $env:PS51_UTF8_RESEARCH_PROBE echo
$ps = [powershell]::Create()
try { $newRunspaceCP = @($ps.AddScript('$OutputEncoding.CodePage').Invoke())[0] } finally { $ps.Dispose() }
[pscustomobject]@{Version=$PSVersionTable.PSVersion.ToString();Bits=([IntPtr]::Size*8);InputCP=[Console]::InputEncoding.CodePage;OutputCP=[Console]::OutputEncoding.CodePage;PipeCP=$OutputEncoding.CodePage;NewRunspaceCP=$newRunspaceCP;DefaultCP=[Text.Encoding]::Default.CodePage;InputMatches=($line -ceq '输入中文😀');NativeMatches=($native -ceq '管道中文😀');Text='输出中文😀';Hook=[AppDomain]::CurrentDomain.GetData('Ps51Utf8Research.Status')} | ConvertTo-Json -Compress
[Console]::Error.Write('错误中文😀')
exit 23
'@
$common = @('-NoLogo', '-NoProfile', '-NonInteractive')
$utf8File = Join-Path $work 'payload-bom 中文.ps1'
[IO.File]::WriteAllText($utf8File, $payload, [Text.UTF8Encoding]::new($true))
$bomlessFile = Join-Path $work 'payload-no-bom.ps1'
[IO.File]::WriteAllText($bomlessFile, "[Console]::Write('文件中文')", [Text.UTF8Encoding]::new($false))

try {
    foreach ($architecture in @('System32', 'SysWOW64')) {
        $original = Join-Path $env:WINDIR "$architecture/WindowsPowerShell/v1.0/powershell.exe"
        if (-not (Test-Path -LiteralPath $original)) { continue }
        $copyDir = Join-Path $work $architecture
        $null = New-Item -ItemType Directory -Path $copyDir
        $copy = Join-Path $copyDir 'powershell.exe'
        Copy-Item -LiteralPath $original -Destination $copy
        Copy-Item -LiteralPath $dll -Destination $copyDir
        # Copy only into this experiment's private directory; never modify Windows files.
        $baseline = Invoke-Child $original ($common + @('-Command', $simple))
        $base = $baseline.Stdout | ConvertFrom-Json
        Record "$architecture original baseline" ($baseline.ExitCode -eq 0 -and $base.PipeCP -eq 20127 -and -not $base.Hook) $base
        $ignored = Invoke-Child $original ($common + @('-Command', $simple)) @{DOTNET_STARTUP_HOOKS=$dll}
        Record "$architecture ignores DOTNET_STARTUP_HOOKS" ($ignored.ExitCode -eq 0 -and $ignored.Stdout -ceq $baseline.Stdout) $ignored
        $consoleOnly = Invoke-Child $copy ($common + @('-Command', $payload)) ($hookEnvironment + @{PS51_UTF8_RESEARCH_CONSOLE_ONLY='1'}) '输入中文😀'
        $console = $consoleOnly.Stdout | ConvertFrom-Json
        Record "$architecture console-only hook leaves native pipeline broken" ($consoleOnly.ExitCode -eq 23 -and $console.InputCP -eq 65001 -and $console.OutputCP -eq 65001 -and $console.PipeCP -eq 20127 -and -not $console.NativeMatches) $console
        foreach ($mode in @('Command', 'EncodedCommand', 'File')) {
            $argument = switch ($mode) {
                'Command' { $payload }
                'EncodedCommand' { [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload)) }
                'File' { $utf8File }
            }
            $run = Invoke-Child $copy ($common + @("-$mode", $argument)) $hookEnvironment '输入中文😀'
            $data = $run.Stdout | ConvertFrom-Json
            Record "$architecture AppDomainManager -NoProfile -$mode" ($run.ExitCode -eq 23 -and $run.ValidUtf8 -and -not $run.HasBom -and $run.Stderr -ceq '错误中文😀' -and $data.InputCP -eq 65001 -and $data.OutputCP -eq 65001 -and $data.PipeCP -eq 65001 -and $data.NewRunspaceCP -eq 65001 -and $data.InputMatches -and $data.NativeMatches -and $data.Text -ceq '输出中文😀' -and $data.Hook -eq 'ConsoleAndPipeline' -and $data.DefaultCP -eq $base.DefaultCP) $data
        }
        $bomless = Invoke-Child $copy ($common + @('-File', $bomlessFile)) $hookEnvironment
        Record "$architecture hook does not change BOM-less script decoding" ($bomless.ExitCode -eq 0 -and $bomless.Stdout -cne '文件中文' -and $base.DefaultCP -ne 65001) $bomless
        $fileDefaults = @'
$ProgressPreference='SilentlyContinue'
'abc' > redirect.txt
'abc' | Set-Content set-content.txt
[pscustomobject]@{Redirect=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $pwd 'redirect.txt')));SetContent=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $pwd 'set-content.txt')))} | ConvertTo-Json -Compress
'@
        $filesBefore = Invoke-Child $original ($common + @('-Command', $fileDefaults))
        $filesAfter = Invoke-Child $copy ($common + @('-Command', $fileDefaults)) $hookEnvironment
        Record "$architecture hook leaves file-output defaults unchanged" ($filesBefore.ExitCode -eq 0 -and $filesAfter.ExitCode -eq 0 -and $filesBefore.Stdout -ceq $filesAfter.Stdout) $filesAfter
        $config = [xml](Get-Content -LiteralPath ($original + '.config') -Raw)
        foreach ($pair in @(@('appDomainManagerAssembly', $assembly), @('appDomainManagerType', $manager))) {
            $element = $config.CreateElement($pair[0])
            $element.SetAttribute('value', $pair[1])
            $null = $config.configuration.runtime.AppendChild($element)
        }
        $config.Save($copy + '.config')
        $configured = Invoke-Child $copy ($common + @('-Command', $simple))
        $configuredData = $configured.Stdout | ConvertFrom-Json
        Record "$architecture application-config hook without environment variables" ($configured.ExitCode -eq 0 -and $configuredData.Hook -eq 'ConsoleAndPipeline' -and $configuredData.PipeCP -eq 65001) $configuredData
    }

    # An unchanged system executable cannot resolve our DLL from an arbitrary directory.
    $systemPs = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $unresolved = Invoke-Child $systemPs ($common + @('-Command', "[Console]::Write('REACHED')")) $hookEnvironment
    Record 'Original executable cannot resolve the private manager assembly' ($unresolved.ExitCode -ne 0 -and $unresolved.Stdout -notmatch 'REACHED') $unresolved
    $absolute = Invoke-Child $systemPs ($common + @('-Command', "[Console]::Write('REACHED')")) @{APPDOMAIN_MANAGER_ASM=$dll;APPDOMAIN_MANAGER_TYPE=$manager}
    Record 'APPDOMAIN_MANAGER_ASM does not accept an arbitrary DLL path' ($absolute.ExitCode -ne 0 -and $absolute.Stdout -notmatch 'REACHED') $absolute

    # Prove that executable filtering only helps AFTER the manager assembly has loaded.
    $otherDir = Join-Path $work 'other-app'
    $null = New-Item -ItemType Directory -Path $otherDir
    $other = Join-Path $otherDir 'FrameworkProbe.exe'
    Copy-Item -LiteralPath $probe -Destination $other
    $normal = Invoke-Child $other @()
    $missing = Invoke-Child $other @() $hookEnvironment
    Record 'Global-style manager variables break an unrelated app without the DLL' ($normal.ExitCode -eq 17 -and $missing.ExitCode -ne 17) $missing
    Copy-Item -LiteralPath $dll -Destination $otherDir
    $skipped = Invoke-Child $other @() $hookEnvironment
    Record 'Unrelated app is skipped once the manager DLL can be loaded' ($skipped.ExitCode -eq 17 -and $skipped.Stdout -ceq ($normal.Stdout + 'Skipped')) $skipped

    foreach ($scope in @('User', 'Machine')) {
        foreach ($name in @('APPDOMAIN_MANAGER_ASM', 'APPDOMAIN_MANAGER_TYPE', 'DOTNET_STARTUP_HOOKS')) {
            Record "$scope $name unchanged" ($settingsBefore["$scope/$name"] -ceq [Environment]::GetEnvironmentVariable($name, $scope)) $null
        }
    }
} finally {
    $report = [pscustomobject]@{CreatedAtUtc=[DateTime]::UtcNow.ToString('o');WorkDirectory=$work;DllSHA256=(Get-FileHash -LiteralPath $dll).Hash;Tests=$results}
    $reportPath = Join-Path $root 'artifacts/ps51-feasibility.json'
    $null = New-Item -ItemType Directory -Path (Split-Path $reportPath -Parent) -Force
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Write-Output "Report: $reportPath"
}
Write-Output "$($results.Count) feasibility checks passed. This experiment did not install a hook."
