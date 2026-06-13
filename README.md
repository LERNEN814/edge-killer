# Edge Killer

[中文说明](README.zh-CN.md)

PowerShell MVP for keeping Microsoft Edge browser absent from a Windows machine.

The tool:

- Removes the current Microsoft Edge browser installation.
- Installs a SYSTEM scheduled task that checks after boot and on an interval.
- Re-runs removal if Edge appears again.
- Writes Microsoft Edge Update policy values that attempt to block future Edge install/update behavior.
- Preserves Microsoft Edge WebView2 Runtime by default.

## Download

Download the latest single-file Windows executable from GitHub Releases:

[Download EdgeKiller.exe](https://github.com/LERNEN814/edge-killer/releases/download/v0.1.0/EdgeKiller.exe)

Release page:

[https://github.com/LERNEN814/edge-killer/releases/tag/v0.1.0](https://github.com/LERNEN814/edge-killer/releases/tag/v0.1.0)

## GUI Wrapper

The WPF wrapper provides a minimal graphical interface:

- Automatically checks status on launch.
- Shows separate status rows for Edge browser, EdgeCore, and Edge WebView2 Runtime.
- Provides a one-click Edge cleanup button.
- Provides an optional checkbox for WebView2 cleanup.
- Re-checks status after cleanup.
- Installs the watchdog automation after cleanup.

The released `EdgeKiller.exe` is self-contained. It does not require the target
machine to install the .NET SDK, Visual Studio, or the .NET Desktop Runtime.

Runtime requirements:

- Windows x64.
- Windows PowerShell 5.1 available as `powershell.exe`.
- Administrator approval at launch.
- System policy must allow the app to start a PowerShell child process with
  `-ExecutionPolicy Bypass`.

## Important Boundaries

Run this only on a machine you own or administer.

Removing Edge can affect Windows features and apps that expect the Edge browser to exist. The default mode avoids removing WebView2 because many applications use WebView2 as an embedded browser runtime.

Microsoft can change Windows and Edge servicing behavior. This tool uses documented policy locations where possible and adds a watchdog because OS updates may still reinstall Edge.

## Quick Start

Open PowerShell as Administrator from this directory:

```powershell
.\edge-killer.ps1 status
.\edge-killer.ps1 install
```

`install` performs all MVP actions:

1. Writes EdgeUpdate blocking policies.
2. Removes the current Edge browser.
3. Installs the boot and interval watchdog task.

If the official Edge uninstaller exits with a non-zero code and `status` still
shows `msedge.exe`, run aggressive mode.

## Commands

```powershell
.\edge-killer.ps1 status
```

Shows detected Edge executables, installers, directories, EdgeUpdate services/tasks, and watchdog state.

`EdgeCore` is treated as Edge browser/core residue and is included in normal
Edge detection. `EdgeWebView` is reported separately as WebView2 Runtime.

```powershell
.\edge-killer.ps1 remove
```

Runs a removal pass. It stops Edge processes, invokes Edge's official installer with uninstall flags when available, and removes common Edge shortcuts.

```powershell
.\edge-killer.ps1 harden
```

Writes EdgeUpdate policy values under:

```text
HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate
```

```powershell
.\edge-killer.ps1 install-watchdog
```

Copies the script to `C:\ProgramData\EdgeKiller` and creates the `EdgeKiller-Watchdog` scheduled task running as `SYSTEM`.

```powershell
.\edge-killer.ps1 install
```

Runs `harden`, `remove`, and `install-watchdog`.

```powershell
.\edge-killer.ps1 restore
```

Removes the watchdog task and restores policy values that Edge Killer changed. This does not reinstall Microsoft Edge.

## Aggressive Mode

```powershell
.\edge-killer.ps1 install -Aggressive
```

Aggressive mode additionally removes Edge directories, Edge user data directories, EdgeUpdate scheduled tasks, EdgeUpdate services, and EdgeUpdate directories.

This is more likely to stop Edge from returning, but it has higher compatibility risk.

Use aggressive mode when the official Edge uninstaller returns a non-zero exit
code such as `93` and the Edge executable remains in `C:\Program Files (x86)`.

Aggressive mode includes `EdgeCore`. It does not remove `EdgeWebView` unless
`-IncludeWebView2` is also supplied.

## WebView2

WebView2 is preserved by default.

Only include it when you have confirmed that no required applications depend on it:

```powershell
.\edge-killer.ps1 install -Aggressive -IncludeWebView2
```

To remove WebView2 explicitly after Edge and EdgeCore have already been removed:

```powershell
.\edge-killer.ps1 remove-webview2 -Force
```

## Watchdog Interval

The default watchdog interval is 30 minutes, with a 90 second boot delay.

```powershell
.\edge-killer.ps1 install -RepeatMinutes 15 -BootDelaySeconds 120
```

## Logs

Logs are written to:

```text
C:\ProgramData\EdgeKiller\logs
```

## Build From Source

To publish the WPF wrapper as a self-contained single-file executable:

```powershell
cd .\windows-wrapper\EdgeKiller.UI
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o .\publish-single
```

Output:

```text
windows-wrapper\EdgeKiller.UI\publish-single\EdgeKiller.exe
```

## Current Architecture

This MVP intentionally uses a scheduled task instead of a Windows service. A SYSTEM scheduled task is simpler to install and remove, avoids a compiled service host, and is enough to satisfy boot-time and recurring checks.

The WPF wrapper embeds a copy of the PowerShell cleanup script and extracts it
to `C:\ProgramData\EdgeKiller.UI\edge-killer.ps1` at runtime.

## License

No open-source license has been declared yet. Add a license before encouraging
reuse or redistribution by others.
