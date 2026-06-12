using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;

namespace EdgeKiller.UI;

public partial class MainWindow : Window
{
    private static readonly Brush DetectedBrush = new SolidColorBrush(Color.FromRgb(220, 38, 38));
    private static readonly Brush ClearBrush = new SolidColorBrush(Color.FromRgb(22, 163, 74));
    private static readonly Brush UnknownBrush = new SolidColorBrush(Color.FromRgb(148, 163, 184));

    private readonly string _scriptPath;
    private bool _busy;

    public MainWindow()
    {
        InitializeComponent();
        _scriptPath = EnsureBundledScript();
        Loaded += MainWindow_Loaded;
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        await RefreshStatusAsync();
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        await RefreshStatusAsync();
    }

    private async void RemoveButton_Click(object sender, RoutedEventArgs e)
    {
        if (_busy)
        {
            return;
        }

        var removeWebView = RemoveWebViewCheckBox.IsChecked == true;
        if (removeWebView)
        {
            var confirm = MessageBox.Show(
                "Removing WebView2 can break applications that embed web content. Continue?",
                "Remove WebView2",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (confirm != MessageBoxResult.Yes)
            {
                return;
            }
        }

        await RunWorkflowAsync(removeWebView);
    }

    private async Task RefreshStatusAsync()
    {
        await SetBusyAsync(true, "Checking status...");
        try
        {
            var result = await RunScriptAsync("status-json");
            AppendLog(result.StdOut);
            if (!result.Success)
            {
                AppendLog(result.StdErr);
                SetUnknownStatus("Status failed");
                return;
            }

            var status = JsonSerializer.Deserialize<EdgeStatus>(ExtractJson(result.StdOut), new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (status is null)
            {
                SetUnknownStatus("No status");
                return;
            }

            ApplyStatus(status);
        }
        catch (Exception ex)
        {
            AppendLog(ex.Message);
            SetUnknownStatus("Error");
        }
        finally
        {
            await SetBusyAsync(false);
        }
    }

    private async Task RunWorkflowAsync(bool removeWebView)
    {
        await SetBusyAsync(true, "Removing Edge...");
        try
        {
            var removeResult = await RunScriptAsync("remove", "-Aggressive");
            AppendLog(removeResult.StdOut);
            AppendLog(removeResult.StdErr);

            if (removeWebView)
            {
                await SetBusyAsync(true, "Removing WebView2...");
                var webViewResult = await RunScriptAsync("remove-webview2", "-Force");
                AppendLog(webViewResult.StdOut);
                AppendLog(webViewResult.StdErr);
            }

            await SetBusyAsync(true, "Installing watchdog...");
            var watchdogResult = await RunScriptAsync("install-watchdog", "-Aggressive");
            AppendLog(watchdogResult.StdOut);
            AppendLog(watchdogResult.StdErr);

            await RefreshStatusAsync();
        }
        finally
        {
            await SetBusyAsync(false);
        }
    }

    private async Task<ScriptResult> RunScriptAsync(params string[] scriptArgs)
    {
        if (!File.Exists(_scriptPath))
        {
            throw new FileNotFoundException("Bundled PowerShell script was not found.", _scriptPath);
        }

        var arguments = new StringBuilder();
        arguments.Append("-NoProfile -ExecutionPolicy Bypass -File ");
        arguments.Append(Quote(_scriptPath));
        foreach (var arg in scriptArgs)
        {
            arguments.Append(' ');
            arguments.Append(arg);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = arguments.ToString(),
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        using var process = new Process { StartInfo = startInfo };
        process.Start();
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        return new ScriptResult(process.ExitCode, await stdoutTask, await stderrTask);
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static string EnsureBundledScript()
    {
        var scriptDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "EdgeKiller.UI");
        Directory.CreateDirectory(scriptDirectory);

        var scriptPath = Path.Combine(scriptDirectory, "edge-killer.ps1");
        var assembly = Assembly.GetExecutingAssembly();
        using var stream = assembly.GetManifestResourceStream("Scripts.edge-killer.ps1")
            ?? throw new InvalidOperationException("Bundled PowerShell script resource was not found.");
        using var file = File.Create(scriptPath);
        stream.CopyTo(file);

        return scriptPath;
    }

    private static string ExtractJson(string text)
    {
        var start = text.IndexOf('{');
        var end = text.LastIndexOf('}');
        if (start < 0 || end < start)
        {
            return text;
        }

        return text[start..(end + 1)];
    }

    private void ApplyStatus(EdgeStatus status)
    {
        var edgeCoreDetected = ContainsPathSegment(status.Executables, "EdgeCore") ||
                               ContainsPathSegment(status.Installers, "EdgeCore") ||
                               ContainsPathSegment(status.Directories, "EdgeCore");
        var edgeBrowserDetected = status.EdgeDetected && !edgeCoreDetected ||
                                  ContainsPathSegment(status.Executables, @"Edge\Application") ||
                                  ContainsPathSegment(status.Directories, @"Edge\Application");

        SetStatus(EdgeDot, EdgeStatusText, edgeBrowserDetected, edgeBrowserDetected ? "Detected" : "Not detected");
        SetStatus(EdgeCoreDot, EdgeCoreStatusText, edgeCoreDetected, edgeCoreDetected ? "Detected" : "Not detected");
        SetStatus(WebViewDot, WebViewStatusText, status.WebView2Detected, status.WebView2Detected ? "Detected" : "Not detected");
    }

    private static bool ContainsPathSegment(string[]? paths, string segment)
    {
        return paths?.Any(path => path.Contains(segment, StringComparison.OrdinalIgnoreCase)) == true;
    }

    private void SetStatus(System.Windows.Shapes.Ellipse dot, System.Windows.Controls.TextBlock label, bool detected, string text)
    {
        dot.Fill = detected ? DetectedBrush : ClearBrush;
        label.Text = text;
        label.Foreground = detected ? DetectedBrush : ClearBrush;
    }

    private void SetUnknownStatus(string text)
    {
        EdgeDot.Fill = UnknownBrush;
        EdgeCoreDot.Fill = UnknownBrush;
        WebViewDot.Fill = UnknownBrush;
        EdgeStatusText.Text = text;
        EdgeCoreStatusText.Text = text;
        WebViewStatusText.Text = text;
    }

    private async Task SetBusyAsync(bool busy, string? message = null)
    {
        _busy = busy;
        RemoveButton.IsEnabled = !busy;
        RefreshButton.IsEnabled = !busy;
        RemoveWebViewCheckBox.IsEnabled = !busy;
        if (!string.IsNullOrWhiteSpace(message))
        {
            AppendLog(message);
        }

        await Task.Yield();
    }

    private void AppendLog(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        LogTextBox.AppendText(text.TrimEnd() + Environment.NewLine);
        LogTextBox.ScrollToEnd();
    }
}

public sealed record ScriptResult(int ExitCode, string StdOut, string StdErr)
{
    public bool Success => ExitCode == 0;
}

public sealed class EdgeStatus
{
    public bool EdgeDetected { get; set; }
    public string[]? Executables { get; set; }
    public string[]? Installers { get; set; }
    public string[]? Directories { get; set; }
    public bool WebView2Detected { get; set; }
    public string[]? WebView2Executables { get; set; }
    public string[]? WebView2Directories { get; set; }
    public string[]? EdgeUpdateTasks { get; set; }
    public string[]? EdgeUpdateServices { get; set; }
    public bool WatchdogInstalled { get; set; }
    public string[]? WatchdogTask { get; set; }
    public string? LogFile { get; set; }
}
