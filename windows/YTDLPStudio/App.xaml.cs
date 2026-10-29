using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using YTDLPStudio.Core;

namespace YTDLPStudio;

public partial class App : Application
{
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        NativeBackdrop.ApplyAccessibleTheme();
        DispatcherUnhandledException += (_, args) =>
        {
            string log = SaveCrash(args.Exception);
            MessageBox.Show("O app encontrou um erro. Detalhes salvos em:\n" + log, "YTDLP Studio", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true; Shutdown(1);
        };
        bool cli = e.Args.Length > 0;
        if (cli) ShutdownMode = ShutdownMode.OnExplicitShutdown;
        try
        {
            if (e.Args is ["--smoke-test", var evidence])
            {
                Directory.CreateDirectory(evidence);
                var window = new MainWindow(automated: true); MainWindow = window; window.Show();
                await Settle();
                SaveWindow(window, Path.Combine(evidence, "download.png"));
                window.AdvancedOptions.IsExpanded = true; await Settle(); SaveWindow(window, Path.Combine(evidence, "advanced.png"));
                window.SelectPage(1); await Settle(); SaveWindow(window, Path.Combine(evidence, "activity.png"));
                window.SelectPage(2); await Settle(); SaveWindow(window, Path.Combine(evidence, "completed.png"));
                window.SelectPage(0); window.Width = 820; window.Height = 680; await Settle(); SaveWindow(window, Path.Combine(evidence, "compact.png"));
                window.Width = 1080; window.Height = 830;
                window.AudioKind.IsChecked = true;
                Check(window.Model.Kind == MediaKind.Audio && window.Model.Container == "mp3", "Alternar para áudio");
                window.VideoKind.IsChecked = true;
                Check(window.Model.Kind == MediaKind.Video && window.Model.Container == "mp4", "Alternar para vídeo");
                window.Model.Links = "invalid-url"; Check(!window.Model.CanAdd, "Bloquear links inválidos");
                window.Model.Links = "https://example.com/watch?v=1\nhttps://example.com/watch?v=2"; Check(window.Model.CanAdd && window.Model.LinkList.Length == 2, "Entrada de lote");
                await WriteJson(Path.Combine(evidence, "smoke-result.json"), new { success = true, platform = Environment.OSVersion.ToString(), framework = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription, checks = new[] { "Window loads", "Native controls and tabs render", "Advanced controls render", "Compact layout renders", "Audio/video bindings", "URL validation", "Batch entry" } });
                window.Close(); Shutdown(0); return;
            }
            if (e.Args is ["--self-test-download", var url, var destination])
            {
                Directory.CreateDirectory(destination);
                try { await Integration(url, destination); Shutdown(0); }
                catch (Exception ex) { await WriteJson(Path.Combine(destination, "integration-result.json"), new { success = false, error = ex.ToString() }); Shutdown(1); }
                return;
            }
            if (cli) throw new ArgumentException("Argumentos não reconhecidos.");
            var main = new MainWindow(); MainWindow = main; main.Show();
        }
        catch (Exception ex) { SaveCrash(ex); if (!cli) MessageBox.Show(ex.Message, "YTDLP Studio", MessageBoxButton.OK, MessageBoxImage.Error); Shutdown(1); }
    }
    private static string SaveCrash(Exception ex)
    {
        string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "YTDLP Studio", "logs", "last-error.txt");
        try { Directory.CreateDirectory(Path.GetDirectoryName(path)!); File.WriteAllText(path, ex.ToString()); } catch { }
        return path;
    }
    private static async Task Settle() { await Task.Delay(180); await Current.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle); }
    private static void Check(bool condition, string check) { if (!condition) throw new InvalidOperationException("Verificação falhou: " + check); }
    private static Task WriteJson(string path, object value) => File.WriteAllTextAsync(path, JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true }));
    private static void SaveWindow(Window window, string path)
    {
        window.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth), (int)Math.Ceiling(window.ActualHeight), 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(window); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path); encoder.Save(stream);
    }
    private async Task Integration(string url, string destination)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(5));
        var token = timeout.Token;
        var window = new MainWindow(automated: true); MainWindow = window; window.Show();
        var model = window.Model;
        var baseUri = new Uri(url); var first = baseUri.AbsoluteUri;
        string Link(int n) => new Uri(baseUri, $"sample{n}.mp4").AbsoluteUri;
        model.Directory = Path.Combine(destination, "Vídeos com espaços"); model.Links = string.Join(Environment.NewLine, new[] { first, Link(2), Link(3) });
        Check(model.CanAdd, "Entrada dos links na interface"); model.AddLinks(); window.SelectPage(1);
        Check(model.ActiveCount == 2 && model.QueuedCount == 1, "Fila com limite de dois processos");
        var cancelled = model.Enqueue(new Uri(baseUri, "cancelled.mp4").AbsoluteUri, new(), model.Directory); model.Cancel(cancelled);
        Check(cancelled.Status == "Cancelado", "Cancelamento de item na fila");
        int maxActive = model.ActiveCount;
        while (model.ActiveCount != 0 || model.QueuedCount != 0) { token.ThrowIfCancellationRequested(); maxActive = Math.Max(maxActive, model.ActiveCount); await Task.Delay(60, token); }
        Check(maxActive == 2, "Limite de concorrência");
        Check(model.DoneCount == 3, "Três downloads reais: " + string.Join(" | ", model.Jobs.Where(x => x.Status == "Falhou").Select(x => x.Error)));
        Check(model.CompletedJobs.All(x => File.Exists(x.File)), "Todos os arquivos finais existem");
        foreach (var job in model.CompletedJobs) await CheckStreams(job.File, requireVideo: true, token);
        await Settle(); SaveWindow(window, Path.Combine(destination, "queue-completed.png"));
        window.SelectPage(2); await Settle(); SaveWindow(window, Path.Combine(destination, "downloads-completed.png"));
        var service = new DownloadService();
        var probe = await service.ProbeAsync(first, token);
        Check(probe.Formats.Count > 0, "Consulta real dos formatos");
        var dialog = new FormatsWindow(first) { Owner = window }; dialog.Show(); await Task.Delay(2500, token); await Settle(); SaveWindow(dialog, Path.Combine(destination, "source-formats.png")); dialog.Close();
        var audio = new List<object>();
        foreach (string format in DownloadCommand.AudioContainers)
        {
            var result = await service.RunAsync(first, new() { Kind = MediaKind.Audio, Container = format }, Path.Combine(destination, "Áudio", format), _ => { }, token);
            await CheckStreams(result.Path, requireVideo: false, token); audio.Add(new { format, path = result.Path, size = new FileInfo(result.Path).Length });
        }
        bool mismatchRejected = false;
        try { await service.RunAsync(first, new() { VideoCodec = "hevc" }, Path.Combine(destination, "mismatch"), _ => { }, token); }
        catch (DownloadException) { mismatchRejected = true; }
        Check(mismatchRejected, "Um codec indisponível deve falhar sem fallback silencioso");
        await WriteJson(Path.Combine(destination, "integration-result.json"), new { success = true, queueDownloads = model.DoneCount, maxConcurrent = maxActive, queuedCancellation = cancelled.Status, sourceFormats = probe.Formats.Count, audio, mismatchRejected, unicodePaths = true, scope = "Synthetic local media; external websites and home Windows desktop remain beta validation." });
        window.Close();
    }
    private static async Task CheckStreams(string path, bool requireVideo, CancellationToken token)
    {
        var info = new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory, "tools", "ffprobe.exe")) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (string arg in new[] { "-v", "error", "-show_entries", "stream=codec_type", "-of", "json", path }) info.ArgumentList.Add(arg);
        using var process = Process.Start(info)!;
        var output = process.StandardOutput.ReadToEndAsync(token); var error = process.StandardError.ReadToEndAsync(token);
        await process.WaitForExitAsync(token); string json = await output; _ = await error;
        Check(process.ExitCode == 0, "FFprobe verifica " + path);
        using var parsed = JsonDocument.Parse(json); var streams = parsed.RootElement.GetProperty("streams").EnumerateArray().Select(x => x.GetProperty("codec_type").GetString()).ToArray();
        Check(streams.Contains("audio") && (requireVideo ? streams.Contains("video") : !streams.Contains("video")), "Faixas esperadas em " + path);
    }
}
