<# 
.SYNOPSIS
  Microsoft Edge removal and watchdog helper for Windows.

.DESCRIPTION
  Edge Killer removes the Microsoft Edge browser, writes EdgeUpdate policy
  guardrails, and can install a SYSTEM scheduled task that checks after boot
  and periodically removes Edge again if Windows reinstalls it.

  The default mode intentionally preserves Microsoft Edge WebView2 Runtime
  because many Windows and third-party apps depend on it.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'status-json', 'remove', 'remove-webview2', 'harden', 'install-watchdog', 'install', 'run-watchdog', 'restore')]
    [string]$Action = 'status',

    [switch]$Aggressive,

    [switch]$IncludeWebView2,

    [switch]$Force,

    [int]$RepeatMinutes = 30,

    [int]$BootDelaySeconds = 90,

    [string]$InstallDir = "$env:ProgramData\EdgeKiller"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Script:ToolName = 'EdgeKiller'
$Script:TaskName = 'EdgeKiller-Watchdog'
$Script:BootTaskName = 'EdgeKiller-Watchdog-Boot'
$Script:IntervalTaskName = 'EdgeKiller-Watchdog-Interval'
$Script:PolicyRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
$Script:BackupRoot = Join-Path $InstallDir 'backup'
$Script:LogRoot = Join-Path $InstallDir 'logs'
$Script:LogFile = Join-Path $Script:LogRoot ("edge-killer-{0:yyyyMMdd}.log" -f (Get-Date))
$Script:ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }

function Initialize-Workspace {
    foreach ($path in @($InstallDir, $Script:BackupRoot, $Script:LogRoot)) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Host $line
    if (Test-Path -LiteralPath $Script:LogRoot) {
        Add-Content -LiteralPath $Script:LogFile -Value $line -Encoding UTF8
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw 'This action requires an elevated PowerShell session. Run PowerShell as Administrator.'
    }
}

function Get-ExistingPath {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }
        $expanded = [Environment]::ExpandEnvironmentVariables($path)
        try {
            if (Test-Path -LiteralPath $expanded -ErrorAction SilentlyContinue) {
                $expanded
            }
        }
        catch {
            Write-Log "Skipping inaccessible path $expanded." 'WARN'
        }
    }
}

function Join-ChildPath {
    param(
        [string]$Root,
        [string]$Child
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return $null
    }

    Join-Path -Path $Root -ChildPath $Child
}

function Get-UniqueExistingDirectories {
    param([string[]]$Paths)

    $seen = @{}
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $expanded = [Environment]::ExpandEnvironmentVariables($path)
        try {
            $exists = Test-Path -LiteralPath $expanded -PathType Container -ErrorAction SilentlyContinue
        }
        catch {
            $exists = $false
        }

        if (-not $exists) {
            continue
        }

        try {
            $resolved = (Resolve-Path -LiteralPath $expanded -ErrorAction Stop).Path
        }
        catch {
            continue
        }
        if (-not $seen.ContainsKey($resolved.ToLowerInvariant())) {
            $seen[$resolved.ToLowerInvariant()] = $true
            $resolved
        }
    }
}

function Get-ProgramFilesRoots {
    Get-UniqueExistingDirectories -Paths @(
        ${env:ProgramFiles(x86)},
        $env:ProgramFiles
    )
}

function Get-LocalAppDataRoots {
    $paths = @($env:LOCALAPPDATA)
    $userRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $userRoot) {
        $paths += Get-ChildItem -LiteralPath $userRoot -Directory -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'AppData\Local' }
    }

    Get-UniqueExistingDirectories -Paths $paths
}

function Get-EdgeInstallers {
    $candidates = @()
    foreach ($root in @(Get-ProgramFilesRoots)) {
        $candidates += Join-ChildPath -Root $root -Child 'Microsoft\Edge\Application\*\Installer\setup.exe'
        $candidates += Join-ChildPath -Root $root -Child 'Microsoft\EdgeCore\*\Installer\setup.exe'
    }
    foreach ($root in @(Get-LocalAppDataRoots)) {
        $candidates += Join-ChildPath -Root $root -Child 'Microsoft\Edge\Application\*\Installer\setup.exe'
        $candidates += Join-ChildPath -Root $root -Child 'Microsoft\EdgeCore\*\Installer\setup.exe'
    }

    foreach ($pattern in $candidates) {
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }
        Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -ExpandProperty FullName
    }
}

function Get-EdgeExecutablePaths {
    $paths = @()
    foreach ($root in @(Get-ProgramFilesRoots)) {
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\Edge\Application\msedge.exe'
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeCore\*\msedge.exe'
    }
    foreach ($root in @(Get-LocalAppDataRoots)) {
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\Edge\Application\msedge.exe'
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeCore\*\msedge.exe'
    }

    if ($IncludeWebView2) {
        $paths += Get-EdgeWebViewExecutablePaths
    }

    Get-ExistingPath -Paths (Expand-PathPatterns -Paths $paths)
}

function Get-EdgeDirectories {
    $paths = @()
    foreach ($root in @(Get-ProgramFilesRoots)) {
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\Edge'
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeCore'
    }
    foreach ($root in @(Get-LocalAppDataRoots)) {
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\Edge\Application'
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeCore'
    }

    if ($IncludeWebView2) {
        $paths += Get-EdgeWebViewDirectories
    }

    Get-ExistingPath -Paths $paths
}

function Expand-PathPatterns {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        if ($path.Contains('*')) {
            Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName
        }
        else {
            $path
        }
    }
}

function Get-EdgeWebViewDirectories {
    $paths = @()
    foreach ($root in @(Get-ProgramFilesRoots)) {
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeWebView'
    }
    foreach ($root in @(Get-LocalAppDataRoots)) {
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeWebView\Application'
    }

    Get-ExistingPath -Paths $paths
}

function Get-EdgeWebViewExecutablePaths {
    $paths = @()
    foreach ($root in @(Get-ProgramFilesRoots)) {
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeWebView\Application\*\msedge.exe'
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeWebView\Application\*\msedgewebview2.exe'
    }
    foreach ($root in @(Get-LocalAppDataRoots)) {
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeWebView\Application\*\msedge.exe'
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeWebView\Application\*\msedgewebview2.exe'
    }

    Get-ExistingPath -Paths (Expand-PathPatterns -Paths $paths)
}

function Get-EdgeUserDataDirectories {
    $roots = @()
    $userRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $userRoot) {
        $roots += Get-ChildItem -LiteralPath $userRoot -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('All Users', 'Default User') } |
            ForEach-Object { Join-Path $_.FullName 'AppData\Local\Microsoft\Edge' }
    }
    Get-ExistingPath -Paths $roots
}

function Get-EdgeUpdateItems {
    $paths = @()
    foreach ($root in @(Get-ProgramFilesRoots)) {
        $paths += Join-ChildPath -Root $root -Child 'Microsoft\EdgeUpdate'
    }

    Get-ExistingPath -Paths $paths
}

function Get-EdgeScheduledTasks {
    $taskNames = @(
        'MicrosoftEdgeUpdateTaskMachineCore',
        'MicrosoftEdgeUpdateTaskMachineUA',
        'MicrosoftEdgeUpdateTaskUser*'
    )

    foreach ($name in $taskNames) {
        Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    }
}

function Get-EdgeServices {
    Get-Service -Name 'edgeupdate', 'edgeupdatem' -ErrorAction SilentlyContinue
}

function Stop-EdgeProcesses {
    param([switch]$WebView2)

    $names = @(
        'msedge',
        'msedge_proxy',
        'msedge_pwa_launcher',
        'pwahelper',
        'identity_helper',
        'elevation_service',
        'elevated_tracing_service',
        'mscopilot',
        'MicrosoftEdgeUpdate'
    )
    if ($Aggressive -or $IncludeWebView2 -or $WebView2) {
        $names += 'msedgewebview2'
    }

    $names = $names | Sort-Object -Unique
    foreach ($name in $names) {
        $processes = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($process in $processes) {
            Write-Log "Stopping process $($process.ProcessName) [$($process.Id)]."
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-EdgeOfficialUninstall {
    $installers = @(Get-EdgeInstallers)
    if ($installers.Count -eq 0) {
        Write-Log 'No Edge installer setup.exe found for official uninstall.' 'WARN'
        return $false
    }

    $succeeded = $false
    foreach ($installer in $installers) {
        Write-Log "Running official Edge uninstall via $installer."
        $arguments = @(
            '--uninstall',
            '--system-level',
            '--verbose-logging',
            '--force-uninstall'
        )

        $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -eq 0) {
            Write-Log "Uninstaller exited with code $($process.ExitCode)."
            $succeeded = $true
        }
        else {
            Write-Log "Uninstaller exited with code $($process.ExitCode); Edge may require aggressive cleanup or OS-level servicing blocked uninstall." 'WARN'
        }
    }

    return $succeeded
}

function Remove-PathIfExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$DirectoryOnly
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $item = Get-Item -LiteralPath $Path -Force
    if ($DirectoryOnly -and -not $item.PSIsContainer) {
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Remove')) {
        Write-Log "Removing $Path."
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to remove $Path. $($_.Exception.Message)" 'WARN'
        }
    }
}

function Remove-EdgeShortcuts {
    $shortcutPaths = @(
        "$env:Public\Desktop\Microsoft Edge.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk"
    )

    $userRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $userRoot) {
        $shortcutPaths += Get-ChildItem -LiteralPath $userRoot -Directory -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                @(
                    (Join-Path $_.FullName 'Desktop\Microsoft Edge.lnk'),
                    (Join-Path $_.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk')
                )
            }
    }

    foreach ($shortcut in $shortcutPaths) {
        if (Test-Path -LiteralPath $shortcut) {
            Remove-PathIfExists -Path $shortcut
        }
    }
}

function Disable-EdgeUpdateServicesAndTasks {
    foreach ($task in @(Get-EdgeScheduledTasks)) {
        Write-Log "Disabling scheduled task $($task.TaskName)."
        Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
    }

    foreach ($service in @(Get-EdgeServices)) {
        Write-Log "Stopping and disabling service $($service.Name)."
        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $service.Name -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

function Remove-EdgeUpdateServicesAndTasks {
    foreach ($task in @(Get-EdgeScheduledTasks)) {
        Write-Log "Unregistering scheduled task $($task.TaskName)."
        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    }

    foreach ($service in @(Get-EdgeServices)) {
        Write-Log "Stopping service $($service.Name)."
        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
        $serviceExe = "$env:SystemRoot\System32\sc.exe"
        & $serviceExe delete $service.Name | Out-Null
    }
}

function Backup-PolicyValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $backupFile = Join-Path $Script:BackupRoot 'edgeupdate-policy-backup.clixml'
    $backup = @{}
    if (Test-Path -LiteralPath $backupFile) {
        $backup = Import-Clixml -LiteralPath $backupFile
    }

    if ($backup.ContainsKey($Name)) {
        return
    }

    if (Test-Path -LiteralPath $Script:PolicyRoot) {
        $property = Get-ItemProperty -LiteralPath $Script:PolicyRoot -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $property) {
            $backup[$Name] = @{
                Exists = $true
                Value = $property.$Name
            }
        }
        else {
            $backup[$Name] = @{ Exists = $false }
        }
    }
    else {
        $backup[$Name] = @{ Exists = $false }
    }

    $backup | Export-Clixml -LiteralPath $backupFile
}

function Set-EdgeUpdatePolicyValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$Value
    )

    if (-not (Test-Path -LiteralPath $Script:PolicyRoot)) {
        New-Item -Path $Script:PolicyRoot -Force | Out-Null
    }

    Backup-PolicyValue -Name $Name
    Write-Log "Setting EdgeUpdate policy $Name=$Value."
    New-ItemProperty -LiteralPath $Script:PolicyRoot -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-EdgeHardening {
    Assert-Administrator
    Initialize-Workspace

    $policyValues = @{
        'InstallDefault' = 0
        'UpdateDefault' = 0
        'AutoUpdateCheckPeriodMinutes' = 0
        'CreateDesktopShortcutDefault' = 0
        'RemoveDesktopShortcutDefault' = 1
        'PreventDesktopShortcutCreationDefault' = 1
    }

    foreach ($entry in $policyValues.GetEnumerator()) {
        Set-EdgeUpdatePolicyValue -Name $entry.Key -Value $entry.Value
    }

    # Edge stable application GUID used by EdgeUpdate policy overrides.
    Set-EdgeUpdatePolicyValue -Name 'Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' -Value 0
    Set-EdgeUpdatePolicyValue -Name 'Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' -Value 0

    if ($Aggressive) {
        Disable-EdgeUpdateServicesAndTasks
    }

    Write-Log 'Hardening completed.'
}

function Restore-PolicyValues {
    $backupFile = Join-Path $Script:BackupRoot 'edgeupdate-policy-backup.clixml'
    if (-not (Test-Path -LiteralPath $backupFile)) {
        Write-Log 'No policy backup found; skipping policy restore.' 'WARN'
        return
    }

    if (-not (Test-Path -LiteralPath $Script:PolicyRoot)) {
        New-Item -Path $Script:PolicyRoot -Force | Out-Null
    }

    $backup = Import-Clixml -LiteralPath $backupFile
    foreach ($name in $backup.Keys) {
        $entry = $backup[$name]
        if ([bool]$entry.Exists) {
            Write-Log "Restoring EdgeUpdate policy $name=$($entry.Value)."
            New-ItemProperty -LiteralPath $Script:PolicyRoot -Name $name -Value ([int]$entry.Value) -PropertyType DWord -Force | Out-Null
        }
        else {
            Write-Log "Removing EdgeUpdate policy $name."
            Remove-ItemProperty -LiteralPath $Script:PolicyRoot -Name $name -ErrorAction SilentlyContinue
        }
    }
}

function Remove-EdgeBrowser {
    Assert-Administrator
    Initialize-Workspace

    Stop-EdgeProcesses -WebView2
    $officialUninstallSucceeded = Invoke-EdgeOfficialUninstall
    Start-Sleep -Seconds 2
    Stop-EdgeProcesses
    Remove-EdgeShortcuts

    if ($Aggressive) {
        foreach ($dir in @(Get-EdgeDirectories)) {
            Remove-PathIfExists -Path $dir -DirectoryOnly
        }

        foreach ($dir in @(Get-EdgeUserDataDirectories)) {
            Remove-PathIfExists -Path $dir -DirectoryOnly
        }

        Remove-EdgeUpdateServicesAndTasks
        foreach ($dir in @(Get-EdgeUpdateItems)) {
            Remove-PathIfExists -Path $dir -DirectoryOnly
        }
    }

    $remainingExecutables = @(Get-EdgeExecutablePaths)
    if ($remainingExecutables.Count -gt 0) {
        if ($Aggressive) {
            Write-Log "Edge executables still remain after aggressive cleanup: $($remainingExecutables -join ', ')." 'WARN'
        }
        elseif (-not $officialUninstallSucceeded) {
            Write-Log "Edge browser still exists and official uninstall did not succeed. Re-run with -Aggressive to remove remaining Edge files/services/tasks." 'WARN'
        }
        else {
            Write-Log "Official uninstall reported success, but Edge executables still remain: $($remainingExecutables -join ', ')." 'WARN'
        }
    }
    else {
        Write-Log 'No Edge browser executable detected after removal pass.'
    }

    Write-Log 'Removal pass completed.'
}

function Remove-WebView2Runtime {
    Assert-Administrator
    Initialize-Workspace

    if (-not $Force) {
        throw 'Removing WebView2 can break applications that embed web content. Re-run with -Force if you intentionally want to remove WebView2.'
    }

    Stop-EdgeProcesses

    foreach ($dir in @(Get-EdgeWebViewDirectories)) {
        Remove-PathIfExists -Path $dir -DirectoryOnly
    }

    $remainingExecutables = @(Get-EdgeWebViewExecutablePaths)
    if ($remainingExecutables.Count -gt 0) {
        Write-Log "WebView2 executables still remain: $($remainingExecutables -join ', ')." 'WARN'
    }
    else {
        Write-Log 'No WebView2 executable detected after removal pass.'
    }

    Write-Log 'WebView2 removal pass completed.'
}

function Get-EdgeStatus {
    Initialize-Workspace

    $executables = @(Get-EdgeExecutablePaths)
    $installers = @(Get-EdgeInstallers)
    $directories = @(Get-EdgeDirectories)
    $webViewDirectories = @(Get-EdgeWebViewDirectories)
    $webViewExecutables = @(Get-EdgeWebViewExecutablePaths)
    $tasks = @(Get-EdgeScheduledTasks)
    $services = @(Get-EdgeServices)
    $watchdogs = @(@(
        Get-ScheduledTask -TaskName $Script:TaskName -ErrorAction SilentlyContinue
        Get-ScheduledTask -TaskName $Script:BootTaskName -ErrorAction SilentlyContinue
        Get-ScheduledTask -TaskName $Script:IntervalTaskName -ErrorAction SilentlyContinue
    ) | Where-Object { $null -ne $_ })

    [PSCustomObject]@{
        EdgeDetected = ($executables.Count -gt 0 -or $installers.Count -gt 0 -or $directories.Count -gt 0)
        Executables = $executables
        Installers = $installers
        Directories = $directories
        WebView2Detected = ($webViewDirectories.Count -gt 0 -or $webViewExecutables.Count -gt 0)
        WebView2Executables = $webViewExecutables
        WebView2Directories = $webViewDirectories
        EdgeUpdateTasks = @($tasks | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" })
        EdgeUpdateServices = @($services | ForEach-Object { "$($_.Name):$($_.Status):$($_.StartType)" })
        WatchdogInstalled = ($watchdogs.Count -gt 0)
        WatchdogTask = @($watchdogs | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" })
        LogFile = $Script:LogFile
    }
}

function Show-Status {
    $status = Get-EdgeStatus
    $status | Format-List
}

function Show-StatusJson {
    $status = Get-EdgeStatus
    $status | ConvertTo-Json -Depth 5 -Compress
}

function Install-Watchdog {
    Assert-Administrator
    Initialize-Workspace

    $installedScript = Join-Path $InstallDir 'edge-killer.ps1'
    $sourcePath = (Resolve-Path -LiteralPath $Script:ScriptPath).Path
    $targetPath = if (Test-Path -LiteralPath $installedScript) {
        (Resolve-Path -LiteralPath $installedScript).Path
    }
    else {
        $installedScript
    }

    if ($sourcePath -ne $targetPath) {
        Write-Log "Installing script to $installedScript."
        Copy-Item -LiteralPath $Script:ScriptPath -Destination $installedScript -Force
    }

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $installedScript),
        'run-watchdog',
        '-InstallDir', ('"{0}"' -f $InstallDir)
    )

    if ($Aggressive) {
        $args += '-Aggressive'
    }
    if ($IncludeWebView2) {
        $args += '-IncludeWebView2'
    }

    $command = 'powershell.exe {0}' -f ($args -join ' ')
    $startTime = (Get-Date).AddMinutes(1).ToString('HH:mm')
    $delayMinutes = [Math]::Floor($BootDelaySeconds / 60)
    $delaySeconds = $BootDelaySeconds % 60
    $bootDelay = '{0:0000}:{1:00}' -f $delayMinutes, $delaySeconds
    $taskNames = @($Script:TaskName, $Script:BootTaskName, $Script:IntervalTaskName)
    foreach ($name in $taskNames) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }

    Write-Log "Registering boot watchdog task $Script:BootTaskName."
    & "$env:SystemRoot\System32\schtasks.exe" /Create /TN $Script:BootTaskName /SC ONSTART /DELAY $bootDelay /RU SYSTEM /RL HIGHEST /TR $command /F | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create boot watchdog task. schtasks.exe exit code: $LASTEXITCODE"
    }

    Write-Log "Registering interval watchdog task $Script:IntervalTaskName."
    & "$env:SystemRoot\System32\schtasks.exe" /Create /TN $Script:IntervalTaskName /SC MINUTE /MO $RepeatMinutes /ST $startTime /RU SYSTEM /RL HIGHEST /TR $command /F | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create interval watchdog task. schtasks.exe exit code: $LASTEXITCODE"
    }

    Write-Log 'Watchdog installed.'
}

function Invoke-Watchdog {
    Initialize-Workspace
    Write-Log 'Watchdog pass started.'
    $status = Get-EdgeStatus

    if ($status.EdgeDetected) {
        Write-Log 'Edge detected by watchdog; running harden and remove.'
        Set-EdgeHardening
        Remove-EdgeBrowser
    }
    else {
        Write-Log 'No Edge installation detected.'
    }
}

function Restore-EdgeKillerChanges {
    Assert-Administrator
    Initialize-Workspace

    foreach ($taskName in @($Script:TaskName, $Script:BootTaskName, $Script:IntervalTaskName)) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Write-Log "Removing watchdog task $taskName."
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    Restore-PolicyValues

    foreach ($service in @(Get-EdgeServices)) {
        Write-Log "Re-enabling service $($service.Name) as Manual."
        Set-Service -Name $service.Name -StartupType Manual -ErrorAction SilentlyContinue
    }

    Write-Log 'Restore completed. This does not reinstall Microsoft Edge.'
}

Initialize-Workspace

try {
    switch ($Action) {
        'status' {
            Show-Status
        }
        'status-json' {
            Show-StatusJson
        }
        'remove' {
            Remove-EdgeBrowser
            Show-Status
        }
        'remove-webview2' {
            Remove-WebView2Runtime
            Show-Status
        }
        'harden' {
            Set-EdgeHardening
            Show-Status
        }
        'install-watchdog' {
            Install-Watchdog
            Show-Status
        }
        'install' {
            Set-EdgeHardening
            Remove-EdgeBrowser
            Install-Watchdog
            Show-Status
        }
        'run-watchdog' {
            Invoke-Watchdog
        }
        'restore' {
            Restore-EdgeKillerChanges
            Show-Status
        }
    }
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
