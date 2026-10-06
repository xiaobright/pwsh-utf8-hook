# Compatibility and validation

Local validation on 2026-10-06 used Windows x64 with ANSI/OEM code page 936
(system-wide UTF-8 disabled) and .NET SDK 10.0.401. One `netstandard2.0` DLL
was used for every case; no per-runtime binaries are required.

| PowerShell | Actual bundled runtime | Installation tested | Result |
| --- | --- | --- | --- |
| 7.2.24 | .NET 6.0.35 | Official portable x64 ZIP | Passed |
| 7.3.12 | .NET 7.0.18 | Official portable x64 ZIP | Passed |
| 7.4.20 | .NET 8.0.31 | Official portable x64 ZIP | Passed |
| 7.5.11 | .NET 9.0.20 | Official portable x64 ZIP | Passed |
| 7.6.5 | .NET 10.0.11 | Application-bundled runtime | Passed |
| 7.6.6 | .NET 10.0.12 | Microsoft Store | Passed |

Each version was launched as an actual `pwsh.exe` child process with `-NoProfile`
and redirected input/output. `-Command`, `-EncodedCommand` and a UTF-8 `-File`
were checked for Chinese and emoji input, stdout and stderr, UTF-8 without a BOM,
native-process pipeline text, and exit code 23. A baseline child without the hook
was also recorded. Every version was retested using the installed DLL in a path
containing spaces and Chinese characters, not just the build output path.

Unrelated console applications were launched on .NET 6.0.36, 7.0.20, 8.0.31 and
10.0.12 with and without the hook: console encodings, stderr and exit codes stayed
unchanged. A separate general .NET 9 application was not tested; .NET 9 was covered
by the PowerShell 7.5 process. Windows PowerShell 5.1 remained unchanged.

Installer tests cover dry-run behavior, DLL hash verification, idempotence,
exact restoration of a missing or existing environment value, preservation of
later-added hooks, and rejection of duplicate hook assemblies, semicolon paths
and LocalAppData installation paths. They use **process scope only** and verify
that user/machine environment settings remain untouched. User-registry writes
are not exercised by the automated suite.

## Reproduce

```powershell
.\scripts\Build.ps1 -Package
$pwsh = .\scripts\Get-TestPowerShell.ps1 -Version 7.2.24
.\scripts\Test.ps1 -PowerShellPaths @($pwsh)
```

The optional downloader requires GitHub CLI, network access and PowerShell 7.4+.
It downloads official PowerShell assets through the GitHub API and verifies the
ZIP against the committed SHA-256 manifest before extracting it. CI runs the
same suite against pinned 7.2, 7.3, 7.4, 7.5 and 7.6 versions.

These are compatibility observations, not a recommendation to deploy unsupported
PowerShell releases. Other patch versions, x86/ARM64, hosted PowerShell engines,
trimmed applications, unusual .NET hosts and non-Windows platforms are not covered.

## Why .NET Standard 2.0?

A startup hook runs inside the application's own runtime. Compiling it for the
newest .NET runtime can make older applications fail before the executable-name
guard gets a chance to run. Targeting .NET Standard 2.0 keeps references to shared
framework APIs available to the tested runtimes; no external runtime dependencies
or assembly-resolution hooks are introduced.

The hook still needs to be loadable by every application that inherits its path.
The guard cannot recover from a missing file, path virtualization, a loader error,
or deployment models that disable startup hooks.
