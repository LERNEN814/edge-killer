# Edge Killer Windows Wrapper Decision

This folder is reserved for the Windows executable wrapper and must not mutate
the root MVP PowerShell script during wrapper development.

## Product goal

Build a small Windows executable with a simple UI:

- Automatically check status on launch.
- Show separate detection rows for Edge, EdgeCore, and Edge WebView2.
- Provide a primary "one-click remove Edge" action.
- Provide an optional checkbox to also remove WebView2.
- After removal, run status again.
- Install or refresh the watchdog so Edge does not return after boot or updates.

## Recommended stack

Use .NET 8 WPF for the executable wrapper.

The wrapper should call a bundled copy of the PowerShell core instead of
reimplementing every Windows cleanup operation in C#.

## Why WPF + PowerShell core

- Produces a normal Windows .exe.
- Uses native Windows UI without a browser dependency.
- Avoids depending on WebView2 for the UI.
- Can request administrator elevation through an application manifest.
- Keeps high-risk system logic in the already tested PowerShell core.
- Can be published as a single-file self-contained executable if needed.

## Architecture

```text
EdgeKiller.UI.exe
  - WPF window
  - status view model
  - elevated process execution
  - bundled Scripts/edge-killer.ps1

Scripts/edge-killer.ps1
  - copied from MVP at wrapper build time
  - invoked for status/remove/remove-webview2/install-watchdog
```

The wrapper should not directly delete system files. It should invoke the
PowerShell script with explicit commands and display the resulting status.

## Command flow

On launch:

```powershell
edge-killer.ps1 status
```

Primary button without WebView2 checked:

```powershell
edge-killer.ps1 remove -Aggressive
edge-killer.ps1 install-watchdog -Aggressive
edge-killer.ps1 status
```

Primary button with WebView2 checked:

```powershell
edge-killer.ps1 remove -Aggressive
edge-killer.ps1 remove-webview2 -Force
edge-killer.ps1 install-watchdog -Aggressive
edge-killer.ps1 status
```

## Alternatives considered

### WinForms + PowerShell core

Simpler than WPF and good enough for a tiny utility, but less flexible for a
clean status layout.

### Native C++ / Win32

Small binary and no .NET dependency, but more development cost and duplicated
cleanup logic.

### Electron / Tauri

Heavier than needed. Electron is especially inappropriate here because the app
is a system cleanup utility and should not ship a large browser runtime.

### WPF with direct C# system cleanup

Possible, but not recommended for the first wrapper. It would duplicate the
PowerShell MVP and increase risk.

## Open implementation notes

- Add machine-readable status output to the bundled script, ideally JSON.
- Add a WPF app manifest with `requireAdministrator`.
- Disable the remove button while operations run.
- Stream script logs into the UI.
- Keep WebView2 deletion behind an explicit checkbox and confirmation text.
- Publish with `dotnet publish -c Release -r win-x64`.
