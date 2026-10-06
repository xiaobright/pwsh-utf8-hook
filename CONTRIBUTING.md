# Contributing

Use Windows, a stable .NET 10 SDK, and PowerShell 7.2+.

```powershell
.\scripts\Build.ps1 -Package
.\scripts\Test.ps1
```

Keep the hook free of third-party runtime dependencies and silent on stdout/stderr.
Do not add profile loading, command rewriting, or system locale changes. Exercise
actual child processes for encoding changes; the installer tests must remain in
process scope. Review the startup-hook compatibility constraints before adding APIs.

The optional portable-version downloader requires GitHub CLI and PowerShell 7.4+
for byte-preserving native output redirection. Downloads are SHA-256 pinned in
`tests/powershell-versions.json`. Older runtimes are test fixtures only.

Keep local reports, package binaries, downloaded runtimes, and installation state
out of Git. When reporting a failure, include PowerShell/.NET versions and launch
mode, and remove personal paths and environment values from logs.
