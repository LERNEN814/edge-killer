# Packaging

## Single-file release

The portable release is:

```text
publish-single\EdgeKiller.exe
```

This executable is self-contained and embeds:

- .NET runtime dependencies required by the WPF application.
- The bundled PowerShell cleanup script.

It does not require the target machine to install the .NET SDK, Visual Studio,
or the .NET Desktop Runtime separately.

## Build command

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o .\publish-single
```

## Runtime requirements

- Windows x64.
- Windows PowerShell 5.1 available as `powershell.exe`.
- Administrator approval at launch.
- System policy must allow PowerShell script execution through the app's
  `-ExecutionPolicy Bypass` child process.

The app writes the embedded script to:

```text
C:\ProgramData\EdgeKiller.UI\edge-killer.ps1
```

The cleanup script continues to write logs to:

```text
C:\ProgramData\EdgeKiller\logs
```
