# Changelog

## Unreleased

- Add an independent Windows PowerShell 5.1 AppDomainManager experiment with
  `net472` projects, isolated x64/x86 feasibility tests and English/Chinese notes.
  The PowerShell 7 hook, installer and release package remain unchanged.

## 1.0.0

- Single `netstandard2.0` startup-hook DLL with no third-party runtime dependencies.
- UTF-8 console input/output for Windows `pwsh.exe`, including `-NoProfile`.
- User or process installation, hash-named DLL versions, existing-hook preservation,
  reversible configuration, and a default path outside LocalAppData.
- Windows compatibility tests for PowerShell 7.2–7.6 and unrelated .NET applications.
