# pwsh-utf8-hook

[English](README.md)

让 Windows 上的 PowerShell 7 在 `-NoProfile` 下也使用 UTF-8 控制台输入和输出，适用于 agent 工具。无需 profile，也无需开启可能影响老程序的系统全局 UTF-8。

实现是一个无第三方运行时依赖、面向 `netstandard2.0` 的小型 DLL。它使用 .NET 的 `DOTNET_STARTUP_HOOKS`，只在实际进程名为 `pwsh.exe` 时设置控制台编码；不改写命令参数，不打印启动消息，不设置 Python 环境变量。PowerShell 7 的 `$OutputEncoding` 本身已默认使用 UTF-8。

## 安装

从 [Releases](https://github.com/xiaobright/pwsh-utf8-hook/releases) 下载 ZIP 并解压，在该目录执行：

```powershell
.\Install.ps1
```

然后完全退出并重新打开 agent 和终端，使它们继承新的环境变量。旧进程启动的子进程仍可能使用旧环境。

安装无需管理员权限。默认目录是 `%USERPROFILE%\Documents\PwshUtf8Hook`，DLL 按内容哈希存放在版本目录中；升级保留旧版本，避免影响还在运行的进程。原环境变量会保存到安装目录的状态文件中。

可用 `-WhatIf` 预览，或用 `-InstallDirectory 'D:\Tools\PwshUtf8Hook'` 指定稳定位置。不要放在 `AppData\Local` 下：Store/MSIX 版 PowerShell 可能看不到与普通程序相同的路径。如果已经配置过本工具的其他安装，请先撤销旧安装。

默认设置当前用户的 `DOTNET_STARTUP_HOOKS`，保留其他已有钩子。仅希望作用于一个父进程时，可使用 `-Scope Process`，随后从该 PowerShell 进程启动 agent。一次性子进程中的环境变更不会反向影响父进程。

## 撤销与恢复

```powershell
.\Uninstall.ps1
```

如果安装时指定了目录或作用域，撤销时使用相同的 `-InstallDirectory`、`-Scope`。配置未被外部修改时恢复原值；如果其他应用后来添加了钩子，只移除本工具自己的条目。撤销后重新启动应用。脚本保留 DLL 和状态文件，不自动删除目录。

如果 PowerShell 7 无法启动，可以使用不支持这种钩子的系统 PowerShell 5.1：

```powershell
powershell.exe -NoProfile -File .\Uninstall.ps1
```

## 范围与限制

- 验证范围为 Windows x64 PowerShell 7.2–7.6；DLL 是 AnyCPU，但未验证 x86/ARM64。具体记录见[兼容性说明](docs/compatibility.md)。旧版进入测试矩阵不代表推荐安装已停止维护的版本。
- 不处理 PowerShell 5.1、`dotnet pwsh.dll`、非 Windows shell，以及清理环境变量或禁用启动钩子的宿主。后续脚本仍可再次改变编码。
- 不会转换已有 GBK 文件，也不能强制所有外部程序输出 UTF-8；调用方仍应按 UTF-8 解码。共享控制台的其他程序可能受到控制台代码页变化影响。
- 其他 .NET 程序也会加载 DLL，但会被立即跳过。**如果 DLL 丢失、无访问权限或损坏，运行时可能在进入钩子代码前就阻止应用启动。必须先撤销环境变量，再移除 DLL。** 未验证裁剪或特殊部署模式，必要时先使用进程作用域。

## 构建与验证

在源码仓库目录构建，需要稳定版 .NET 10 SDK，以及运行构建/测试脚本的 PowerShell 7.2+。DLL 目标是 .NET Standard 2.0，不依赖目标机器安装 .NET 10 SDK；构建时会还原所需引用程序集。

```powershell
.\scripts\Build.ps1 -Package
.\scripts\Test.ps1
.\scripts\Test.ps1 -PowerShellPaths @('D:\PS72\pwsh.exe', 'D:\PS76\pwsh.exe')
```

测试通过实际子进程验证 `-NoProfile` 下的三种入口、中文和 emoji 输入输出、BOM、原生管道、退出码及其他 .NET 应用不受影响。安装脚本测试只使用进程环境和临时目录，不修改用户或系统环境变量。构建产物和 JSON 测试报告位于忽略提交的 `artifacts` 目录。

MIT 许可证。发布包含 DLL、安装/撤销脚本、文档和 SHA-256 校验值。
