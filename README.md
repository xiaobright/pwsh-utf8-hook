# pwsh-utf8-hook

[简体中文](README.zh-CN.md)

Make PowerShell 7 use UTF-8 for console input and output on Windows, including
`pwsh -NoProfile` launched by agent tools. Keep the Windows system code page
unchanged for older applications.

A small, dependency-free `netstandard2.0` DLL uses the supported
[.NET startup-hook mechanism](https://github.com/dotnet/runtime/blob/main/docs/design/features/host-startup-hook.md).
It checks that the actual executable is `pwsh.exe`, then sets
`Console.InputEncoding` and `Console.OutputEncoding` to UTF-8 without a BOM.
It does not load profiles, rewrite command arguments, print startup messages,
or change Python environment variables. PowerShell 7's `$OutputEncoding` already
defaults to UTF-8.

## Install

1. Download and extract the ZIP from [Releases](https://github.com/xiaobright/pwsh-utf8-hook/releases).
2. Run the included installer from that directory:

   ```powershell
   .\Install.ps1
   ```

3. Completely exit and reopen your agent applications and terminals. Children
   of an already-running application may still inherit the old environment.

The installer needs no administrator rights. It copies the DLL to a hash-named
version directory under `%USERPROFILE%\Documents\PwshUtf8Hook`, backs up the
previous value, and adds it to the **user** `DOTNET_STARTUP_HOOKS` environment
variable. Existing hooks are preserved. DLL versions are retained during updates
so running applications do not lose the files they reference.

Use `-WhatIf` to preview, or `-InstallDirectory 'D:\Tools\PwshUtf8Hook'` to choose
a stable directory. Avoid `AppData\Local`: Store/MSIX PowerShell may not see the
same path as an unpackaged application. The default intentionally avoids it.
If another installation of this hook is already configured, disable it first.

For a single parent process instead of all applications, use `-Scope Process`.
Only that PowerShell process and children started from it inherit the change;
running the installer inside a disposable child shell will not change its parent.

## Uninstall / recovery

```powershell
.\Uninstall.ps1
```

Pass the same `-InstallDirectory` and `-Scope` used for installation, if customized.
The script restores the original setting when it is unchanged, or removes only
this DLL's entry if another application has since added hooks. Restart affected
applications afterwards. Files are retained; uninstall **before** deleting them.

If PowerShell 7 cannot start, use the built-in Windows PowerShell 5.1, which does
not use .NET startup hooks:

```powershell
powershell.exe -NoProfile -File .\Uninstall.ps1
```

## Scope and limitations

- Windows x64 PowerShell 7.2–7.6 are covered by the compatibility suite. The
  DLL is AnyCPU, but x86/ARM64 are not validated. See [compatibility](docs/compatibility.md).
- No change to Windows PowerShell 5.1, `dotnet pwsh.dll`, or non-Windows shells.
- Applications that clear the environment, disable startup hooks, or embed the
  PowerShell engine can bypass this mechanism. Later code can change encoding again.
- It cannot convert existing GBK files or force a native program to emit UTF-8.
  The caller must also decode stdout/stderr as UTF-8. Programs sharing a console
  may observe the console code-page change.
- `DOTNET_STARTUP_HOOKS` is also inherited by other .NET applications. The DLL
  loads and immediately skips them. **A missing, inaccessible, or corrupt DLL can
  stop those applications before our code runs.** Keep the installed DLL available
  until the environment setting has been removed. Trimming and unusual deployment
  models are not covered; start with process scope if your application requires it.
- PowerShell 7.2/7.3 are included to test compatibility, not as a recommendation
  to install unsupported runtimes.

## Build and verify

From a source checkout, use a stable .NET 10 SDK and PowerShell 7.2+ for the build/test scripts.
The resulting hook targets .NET Standard 2.0, not .NET 10, and has no runtime
NuGet dependencies. Older target reference assemblies are restored at build time.

```powershell
.\scripts\Build.ps1 -Package
.\scripts\Test.ps1
```

To test additional portable PowerShell installations:

```powershell
.\scripts\Test.ps1 -PowerShellPaths @('D:\PS72\pwsh.exe', 'D:\PS76\pwsh.exe')
```

Tests launch real child processes with redirected streams, exercise `-Command`,
`-EncodedCommand` and UTF-8 `-File` under `-NoProfile`, check Unicode, BOMs,
native pipelines and exit codes, and compare unrelated .NET applications with
and without the hook. Installer tests use process scope and temporary directories;
they never change your user/machine environment variables. JSON reports go to
the ignored `artifacts` directory. CI also tests older portable PowerShell releases.

MIT licensed. Release ZIPs include the DLL, installers, documentation and SHA-256.
