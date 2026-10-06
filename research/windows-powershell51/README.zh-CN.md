# Windows PowerShell 5.1 UTF-8 hook 可行性研究

[English](README.md)

本目录保留独立的 5.1 DLL 实验：**通过 AppDomainManager 在 `-NoProfile` 下初始化控制台与管道编码。** 源码、测试程序和复现脚本均与 PowerShell 7 的 hook 分开，没有安装器，也不加入主解决方案、CI 矩阵或发行 ZIP。

| 文件 | 用途 |
| --- | --- |
| [Ps51Utf8Research/DomainManager.cs](Ps51Utf8Research/DomainManager.cs) | 启动 DLL，设置控制台编码及管道默认值 |
| [FrameworkProbe/Program.cs](FrameworkProbe/Program.cs) | 原生管道回显及无关 .NET Framework 应用对照 |
| [Test-Feasibility.ps1](Test-Feasibility.ps1) | 构建两个项目，在隔离子进程中复现检查 |

## 实测环境与命令选择

2026-10-06，在 Windows、系统 ACP/OEMCP 为 936 的环境中验证：

| 实际启动的程序 | 版本 / 运行时 | 本次用途 |
| --- | --- | --- |
| `System32/WindowsPowerShell/v1.0/powershell.exe` | 5.1.26100.9444 / .NET Framework 4.8.1，64 位 | 原程序对照、隔离副本实验 |
| `SysWOW64/WindowsPowerShell/v1.0/powershell.exe` | 5.1.26100.9444 / .NET Framework 4.8.1，32 位 | 原程序对照、隔离副本实验 |
| agent 环境中的 `pwsh.exe` | 7.6.5 / 现代 .NET | 已有 UTF-8 hook 保持有效 |

从本次 agent 环境启动的 Git Bash（不加载 profile）中，`powershell` 解析到系统的 5.1，`pwsh` 解析到 agent 自带的 7。Windows Terminal 的默认配置不会把 `powershell.exe` 自动改成 `pwsh.exe`。其他后端要看它实际启动的可执行文件；PATH、绝对路径和嵌入式宿主可能产生不同结果。

原始 5.1 的 `$OutputEncoding` 均为 ASCII（20127）。本次对照中，64 位进程的控制台编码已经是 65001，32 位为 936：**不能仅凭控制台显示 UTF-8，就判断 PowerShell 原生管道也正常。**

## 已证实的机制

PowerShell 7 使用的 `DOTNET_STARTUP_HOOKS` 在 Windows PowerShell 5.1 中不起作用，实测设置前后无变化。

.NET Framework 提供另一种启动机制：继承 `AppDomainManager`，覆盖 `InitializeNewDomain`，通过以下二选一方式让 CLR 加载它：

- `APPDOMAIN_MANAGER_ASM` 与 `APPDOMAIN_MANAGER_TYPE` 环境变量。
- 应用程序 `.exe.config` 的 `appDomainManagerAssembly` 与 `appDomainManagerType` 元素。

加载发生在 PowerShell 的用户命令和 profile 之前，因此 `-NoProfile` 不会跳过它。本实验仅给独立子进程设置环境变量，或修改工作目录内的 `powershell.exe` 副本配置。

DLL 做两件事：

1. 把 `Console.InputEncoding` 和 `Console.OutputEncoding` 设为无 BOM 的 UTF-8。
2. 通过反射替换 `InitialSessionState.BuiltInVariables` 中的 `OutputEncoding` 默认条目，保留原有描述、选项与类型转换属性，使后续创建的 runspace 使用 UTF-8 管道编码。

第二步使用 **PowerShell 私有字段**，是本实验的维护风险。只完成第一步时，控制台正确，但中文/emoji 经 PowerShell 管道送入原生程序仍然丢失。单纯把现有 DLL 重新编译成 .NET Framework 版本并不足够。

## 验证结果

标准 SDK `.csproj` 面向 `net472` 构建，无外部运行时依赖。两项目构建成功，0 警告、0 错误。28 项隔离检查通过：

- x64 / x86 均验证 `-NoProfile -Command`、`-EncodedCommand` 和带 UTF-8 BOM 的 `-File`。
- 中文和 emoji 的标准输入、输出、错误输出以及原生管道往返正确；输出无 BOM；保留测试退出码 23。
- 初始 runspace 和额外创建的 runspace 的管道编码均为 65001。
- `.exe.config` 方式不依赖上述环境变量也能运行。
- 原系统程序找不到实验 DLL 时不能启动，返回 `Starting the CLR failed with HRESULT 80131522.`。
- 直接把任意 DLL 的绝对路径填入 `APPDOMAIN_MANAGER_ASM` 也不能启动，返回 HRESULT `80131047`。
- 把这组环境变量传给一个无关 .NET Framework 程序：缺少可解析的 DLL 时，该程序会在入口执行前失败；DLL 可解析时，原型能按进程名跳过，不改变其控制台编码。
- 用户级、机器级的两项 AppDomainManager 设置及现有 `DOTNET_STARTUP_HOOKS` 均保持不变。

测试同时保留 stdout/stderr 原始字节的 Base64；CLR 加载错误可能是 UTF-16LE 或系统编码，不能把错误输出一概当作 UTF-8。

## 为什么不直接全局安装

| 方案 | 可行性与代价 |
| --- | --- |
| 用户目录 DLL + 两个用户环境变量 | **不等价于现有 7 的安装方式。** CLR 按程序集身份解析；原系统程序无法在任意用户目录找到 DLL。全局设置后，还会影响继承环境的其他 .NET Framework 程序。 |
| 强名称 DLL + GAC + 环境变量 | 微软文档支持的加载路线，理论上能覆盖原始 `powershell.exe`；需要管理权限和完整的安装、更新、卸载方案。也会参与其他 .NET Framework 应用的启动，并可能冲突于已有 AppDomainManager。本轮未安装或验证 GAC。 |
| 修改真实 `powershell.exe.config` | 可以把作用范围限定到这个宿主；但本机该文件归 TrustedInstaller 所有，Administrators 也只有读取/执行权限。x64/x86 配置分别维护，还要考虑系统更新。本轮仅验证了副本配置。 |
| 原生 CLR Profiler DLL | 有启动加载机制，但需要原生 COM/profiling 实现，进程一次只能使用一个 profiler；要可靠设置 PowerShell 管道还需额外引擎初始化方案。本轮仅查文档，未实现，不能视为已验证替代品。 |
| 独立 launcher / PATH shim | 更容易限制影响范围，但需保留 `-Command`、`-EncodedCommand`、`-File`、标准流、退出码等语义。硬编码系统绝对路径的后端会绕过 PATH shim。本轮未实现。 |

仅复制 `powershell.exe` 是测试 CLR 加载的办法，不是建议的部署方式：其资源、模块、PSHOME、更新和安全策略还需验证。文件名判断也是范围控制，不是安全边界。

## 不能顺带解决的问题

- **无 BOM 的 UTF-8 `.ps1`**：5.1 仍按系统 ANSI 编码读取。实验中的 `文件中文` 变成 `鏂囦欢涓枃`。应保存为带 BOM 的 UTF-8，或使用正确编码的 `-EncodedCommand`。
- **文件读写默认值**：`>` / `Out-File` 仍默认 UTF-16LE，`Set-Content` 默认值也没有改变。需要显式指定编码；5.1 的 `-Encoding UTF8` 会写 BOM。
- **非 UTF-8 原生程序**：hook 不能让硬编码 GBK 的外部工具自动改用 UTF-8；调用方也必须正确解码标准输出。
- **独立启动的新 PowerShell、后台作业、远程会话、嵌入式 PowerShell**：一个 runspace 的成功不代表这些宿主都已覆盖，本轮未验证。

这些限制意味着，支持 5.1 hook 可以改善一部分 agent 调用，但不会把 5.1 整体变成 PowerShell 7 的编码行为。

## 日常使用建议

普通 agent 后端优先显式选择 `pwsh.exe`。可以在 AGENTS.md 中写：

```text
Windows 上执行 PowerShell 命令时使用 pwsh.exe，包括从 Git Bash 中调用。
只有任务明确要求 Windows PowerShell 5.1 时才使用 powershell.exe。
```

必须运行 5.1 且能控制命令入口时，可在同一条命令的开头设置：

```powershell
$utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
# 在这里执行实际命令
```

这不依赖 profile。给 `-EncodedCommand` 的完整命令仍必须按 UTF-16LE 编码后再做 Base64。控制台与管道设置不改变脚本文件的解析编码。

仓库保留 DLL 和复现实验，供有需要的人继续研究，不提供全局安装流程。

## 复现

在 Windows 上安装 .NET SDK 与 .NET Framework 4.7.2 targeting pack，使用 PowerShell 7.2+。从仓库根目录只构建 DLL：

```powershell
dotnet build .\research\windows-powershell51\Ps51Utf8Research\Ps51Utf8Research.csproj -c Release
```

产物为 `research/windows-powershell51/Ps51Utf8Research/bin/Release/net472/Ps51Utf8Research.dll`。构建两个项目并复现检查：

```powershell
.\research\windows-powershell51\Test-Feasibility.ps1
```

测试面向本轮系统 ANSI 非 UTF-8 的场景；会创建 `work/ps51-research-*` 隔离目录，保留测试副本和生成文件，输出 `artifacts/ps51-feasibility.json`。不写入 Windows 目录、GAC、注册表、PATH、profile 或用户/机器环境变量。实验 DLL 位于 `Ps51Utf8Research/bin/Release/net472/Ps51Utf8Research.dll`，不要把实验环境变量手工设成全局。

没有验证历史 5.1 补丁版本、Windows Server、ARM64、实际 agent 产品矩阵或正式安装流程。检索发现通用 AppDomainManager 示例，但没有找到可直接采用、已完成这些验证的专用 5.1 UTF-8 工具；这不是对所有开源项目的穷尽结论。

## 资料

- [Microsoft: AppDomainManager](https://learn.microsoft.com/en-us/dotnet/api/system.appdomainmanager?view=netframework-4.8.1)：启动环境变量、加载位置、完全信任要求。
- [Microsoft: appDomainManagerAssembly](https://learn.microsoft.com/en-us/dotnet/framework/configure-apps/file-schema/runtime/appdomainmanagerassembly-element)：应用配置、加载失败及进程无法启动的行为。
- [Microsoft: PowerShell 字符编码](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding?view=powershell-5.1)：5.1 的脚本与文件编码规则。
- [Microsoft: 与 Windows PowerShell 的差异](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell)：新版本将 `$OutputEncoding` 从 ASCII 改为无 BOM UTF-8。
- [Microsoft: CLR profiling environment](https://learn.microsoft.com/en-us/dotnet/framework/unmanaged-api/profiling/setting-up-a-profiling-environment)：原生 profiler 的约束。
