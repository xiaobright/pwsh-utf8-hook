# Windows PowerShell 5.1 feasibility experiment

[Detailed findings in Chinese](README.zh-CN.md)

A separate .NET Framework `AppDomainManager` DLL can initialize UTF-8 before
Windows PowerShell 5.1 executes a command, including `-NoProfile`. This directory
keeps the experiment separate from the PowerShell 7 hook, with its own DLL,
test program and reproduction script. It has no installer and is not part of
the main solution, CI matrix, or release package.

| File | Purpose |
| --- | --- |
| [Ps51Utf8Research/DomainManager.cs](Ps51Utf8Research/DomainManager.cs) | Experimental startup DLL; console initialization and pipeline default patch |
| [FrameworkProbe/Program.cs](FrameworkProbe/Program.cs) | Native-pipeline echo and unrelated .NET Framework application checks |
| [Test-Feasibility.ps1](Test-Feasibility.ps1) | Builds both projects and runs isolated child-process tests |

## Findings

- `powershell.exe` and `pwsh.exe` are different programs. Selecting a default
  terminal profile does not redirect calls to `powershell.exe` to PowerShell 7.
- Windows PowerShell 5.1 ignores `DOTNET_STARTUP_HOOKS`.
- `AppDomainManager` can run before PowerShell initializes its runspace. The
  prototype sets both console encodings and replaces the `OutputEncoding` entry
  in the private `InitialSessionState.BuiltInVariables` array. The latter is an
  **unsupported internal API**, required by this prototype to fix 5.1's ASCII
  native-pipeline default. Console settings alone did not fix the pipeline.
- The manager DLL must be resolvable through .NET Framework assembly loading;
  an arbitrary absolute DLL path in `APPDOMAIN_MANAGER_ASM` did not work. The
  documented deployment locations are the application directory or GAC.
- Global manager environment variables can stop unrelated .NET Framework apps
  before their entry point if the DLL cannot be loaded. Checking the executable
  name inside the DLL is too late to prevent a loader failure.
- Application-specific `.exe.config` settings also work, but the original
  Windows configuration files are protected; experiments only changed copies.
- UTF-8 script files without a BOM still use the system ANSI decoding in 5.1.
  File-output defaults such as UTF-16LE for `>` also remain unchanged.

## Observed validation

On 2026-10-06, 28 checks passed on Windows PowerShell 5.1.26100.9444, both x64 and
x86, with .NET Framework 4.8.1 and Windows ACP/OEMCP 936. Both SDK projects target
`net472` and built with zero warnings and errors.

The suite checks `-NoProfile -Command`, `-EncodedCommand`, UTF-8-with-BOM `-File`,
Unicode stdin/stdout/stderr, native-pipeline round trips, an additional runspace,
no output BOM, exit codes, application configuration, loader failures, unrelated
.NET Framework apps, and unchanged user/machine environment settings. Raw stream
bytes are preserved as Base64 because startup errors may use UTF-16LE or the
system encoding. A console already reporting 65001 does not prove the pipeline
is configured correctly: the x64 baseline in this environment still used ASCII
for `$OutputEncoding`.

The suite uses copied executables to isolate the experiment. Copying the system
PowerShell executable is **not a validated deployment strategy**. Historical
patches, ARM64, Server, jobs, remoting, embedded hosts, real agent integrations,
GAC installation and native CLR profilers were not tested.

## Reproduce

Use Windows, PowerShell 7.2+, a .NET SDK and the .NET Framework 4.7.2 targeting
pack. The assertions target a Windows system whose ANSI code page is not UTF-8.
Run from the repository root to build just the DLL:

```powershell
dotnet build .\research\windows-powershell51\Ps51Utf8Research\Ps51Utf8Research.csproj -c Release
```

The output is `research/windows-powershell51/Ps51Utf8Research/bin/Release/net472/Ps51Utf8Research.dll`.
To build both projects and reproduce the checks:

```powershell
.\research\windows-powershell51\Test-Feasibility.ps1
```

This builds the experiment and keeps isolated artifacts in `work/ps51-research-*`.
Results are written to `artifacts/ps51-feasibility.json`. It does not install a
hook or modify Windows files, the GAC, registry, PATH, profiles, or user/machine
environment variables. Do not persist the research manager variables globally.

## Agent configuration

For everyday agent commands, explicitly select `pwsh.exe`. For example, add this
to the agent's instructions:

```text
On Windows, use pwsh.exe for PowerShell commands, including calls from Git Bash.
Use powershell.exe only when the task explicitly requires Windows PowerShell 5.1.
```

When 5.1 is required and its command entry point can be configured, prepend
console and pipeline UTF-8 initialization in that same command; see the
[example and encoding limitations](README.zh-CN.md#日常使用建议). This repository
keeps the DLL as a reproducible experiment without a global installation flow.

## Primary references

- [AppDomainManager](https://learn.microsoft.com/en-us/dotnet/api/system.appdomainmanager?view=netframework-4.8.1)
- [appDomainManagerAssembly](https://learn.microsoft.com/en-us/dotnet/framework/configure-apps/file-schema/runtime/appdomainmanagerassembly-element)
- [PowerShell character encoding](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding?view=powershell-5.1)
- [Differences from Windows PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell)
- [CLR profiling environment](https://learn.microsoft.com/en-us/dotnet/framework/unmanaged-api/profiling/setting-up-a-profiling-environment)
