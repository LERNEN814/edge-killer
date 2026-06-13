# Edge Killer

Edge Killer 是一个用于清除 Microsoft Edge 浏览器并阻止其自动回归的 Windows 工具。

项目包含两部分：

- PowerShell MVP：系统级清理脚本，适合排查和自动化。
- WPF 图形界面：单文件 `.exe`，提供状态检测和一键清除入口。

> 请只在你拥有或有权管理的电脑上使用本工具。

## 下载

最新版本可在 GitHub Releases 下载：

[下载 EdgeKiller.exe](https://github.com/LERNEN814/edge-killer/releases/download/v0.1.0/EdgeKiller.exe)

Release 页面：

[https://github.com/LERNEN814/edge-killer/releases/tag/v0.1.0](https://github.com/LERNEN814/edge-killer/releases/tag/v0.1.0)

## 主要功能

- 检测 Edge 浏览器本体是否存在。
- 检测 `EdgeCore` 核心残留是否存在。
- 单独检测 Edge WebView2 Runtime。
- 一键清除 Edge 和 EdgeCore。
- 可选清除 WebView2。
- 写入 EdgeUpdate 策略，尽量阻止自动安装和更新。
- 创建 SYSTEM 权限计划任务，在开机后和定时周期内自动检查 Edge 是否回归。
- 保留日志，便于排查。

## 图形界面版本

可执行文件位于发布包：

```text
EdgeKiller.exe
```

它是自包含单文件程序，不需要目标机器安装：

- .NET SDK
- Visual Studio
- .NET Desktop Runtime

运行要求：

- Windows x64
- 系统自带 Windows PowerShell 5.1，也就是 `powershell.exe`
- 管理员权限
- 系统策略允许程序使用 `-ExecutionPolicy Bypass` 启动 PowerShell 子进程

程序启动后会自动检测：

- Edge browser
- EdgeCore
- Edge WebView2 Runtime

点击 `One-click remove Edge` 后，程序会：

1. 清除 Edge 和 EdgeCore。
2. 如果勾选 `Also remove WebView2`，额外清除 WebView2。
3. 安装 watchdog 自动化任务。
4. 再次检测状态。

## 关于 WebView2

默认不删除 WebView2。

WebView2 不是普通浏览器入口，而是很多桌面应用用来嵌入网页内容的运行时。删除 WebView2 可能导致某些应用的登录页、授权页、设置页、帮助页或内嵌网页界面无法打开。

如果你确认本机没有软件依赖 WebView2，可以在图形界面里勾选 `Also remove WebView2`，或使用命令行：

```powershell
.\edge-killer.ps1 remove-webview2 -Force
```

## PowerShell MVP 用法

以管理员身份打开 PowerShell：

```powershell
cd F:\edge-killer
.\edge-killer.ps1 status
```

一键执行策略加固、清除和 watchdog 安装：

```powershell
.\edge-killer.ps1 install
```

如果官方卸载器失败，或 `EdgeCore` 仍然存在，使用强硬模式：

```powershell
.\edge-killer.ps1 remove -Aggressive
.\edge-killer.ps1 install-watchdog -Aggressive
```

查看状态：

```powershell
.\edge-killer.ps1 status
```

撤销本工具写入的策略和 watchdog：

```powershell
.\edge-killer.ps1 restore
```

`restore` 不会重新安装 Edge。

## 自动化机制

工具会创建 SYSTEM 权限的计划任务：

- 开机后延迟运行一次。
- 每隔一段时间重复检查。

如果检测到 Edge 或 EdgeCore 回归，watchdog 会再次执行清理。

默认检查间隔为 30 分钟，开机延迟为 90 秒。PowerShell 版本可自定义：

```powershell
.\edge-killer.ps1 install-watchdog -RepeatMinutes 15 -BootDelaySeconds 120
```

## 日志位置

清理脚本日志：

```text
C:\ProgramData\EdgeKiller\logs
```

图形界面运行时释放的脚本位置：

```text
C:\ProgramData\EdgeKiller.UI\edge-killer.ps1
```

## 从源码构建

需要 .NET SDK 和 Windows Desktop workload 支持。

进入 WPF 项目目录：

```powershell
cd .\windows-wrapper\EdgeKiller.UI
```

发布自包含单文件 EXE：

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o .\publish-single
```

输出文件：

```text
windows-wrapper\EdgeKiller.UI\publish-single\EdgeKiller.exe
```

## 项目结构

```text
edge-killer.ps1
  PowerShell MVP 主脚本

windows-wrapper\EdgeKiller.UI
  WPF 图形界面项目

windows-wrapper\EdgeKiller.UI\Scripts\edge-killer.ps1
  WPF 包装使用的脚本副本，包含 JSON 状态输出
```

## 重要提示

Microsoft 可能通过 Windows Update 或系统组件策略重新安装 Edge。本工具通过策略和 watchdog 降低回归概率，但不能保证永久抵抗所有未来系统更新行为。

删除 Edge 可能影响依赖 Edge 的 Windows 功能、PWA、搜索体验、组件跳转或其他系统体验。请在理解风险后使用。

## License

当前项目尚未声明开源许可证。若你计划公开分发或允许他人复用代码，建议后续添加明确许可证。
