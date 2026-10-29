using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using YTDLPStudio.Core;

internal static class Program
{
    private static int assertions;
    private static void Assert(bool condition, string message)
    {
        assertions++; if (!condition) throw new Exception("ASSERT: " + message);
    }
    private static void Throws<T>(Action action) where T : Exception
    {
        try { action(); } catch (T) { assertions++; return; }
        throw new Exception("Expected " + typeof(T).Name);
    }
    private static async Task<T> ThrowsAsync<T>(Func<Task> action) where T : Exception
    {
        try { await action(); } catch (T ex) { assertions++; return ex; }
        throw new Exception("Expected " + typeof(T).Name);
    }
    private static async Task<int> Main(string[] args)
    {
        if (args.Contains("--fake-child"))
        {
            File.WriteAllText(Environment.GetEnvironmentVariable("STUDIO_TEST_CHILD")!, Environment.ProcessId.ToString());
            await Task.Delay(Timeout.Infinite); return 0;
        }
        if (Environment.GetEnvironmentVariable("STUDIO_TEST_FAKE") is { } mode) return await Fake(mode, args);
        var evidenceIndex = Array.IndexOf(args, "--evidence");
        if (evidenceIndex >= 0 && evidenceIndex + 1 >= args.Length) throw new ArgumentException("--evidence requires a directory.");
        var evidence = Path.GetFullPath(evidenceIndex >= 0 ? args[evidenceIndex + 1] : Path.Combine(Path.GetTempPath(), "YTDLP Core evidence " + Guid.NewGuid().ToString("N")));
        Directory.CreateDirectory(evidence);
        try
        {
            UnitTests(evidence);
            await ProcessTests(evidence);
            var integrationIndex = Array.IndexOf(args, "--integration-tools");
            if (integrationIndex >= 0)
            {
                if (integrationIndex + 1 >= args.Length) throw new ArgumentException("--integration-tools requires a tools directory.");
                await Integration(Path.GetFullPath(args[integrationIndex + 1]), evidence);
            }
            Console.WriteLine($"PASS {assertions} assertions. Evidence: {evidence}");
            File.WriteAllText(Path.Combine(evidence, "result.txt"), $"PASS {assertions} assertions\n");
            return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); File.WriteAllText(Path.Combine(evidence, "failure.txt"), ex.ToString()); return 1; }
    }
    private static void UnitTests(string evidence)
    {
        var options = new DownloadOptions();
        Assert(options.Kind == MediaKind.Video && options.Container == "mp4", "defaults");
        Assert(DownloadCommand.VideoContainers.Count == 8 && DownloadCommand.AudioContainers.Count == 12, "all formats");
        foreach (var container in DownloadCommand.VideoContainers)
        {
            var args = DownloadCommand.Arguments("https://example.test/video", options with { Container = container }, evidence);
            Assert(args.Contains("--remux-video") == (container != "auto"), "video " + container);
        }
        foreach (var container in DownloadCommand.AudioContainers)
        {
            var args = DownloadCommand.Arguments("https://example.test/video", options with { Kind = MediaKind.Audio, Container = container }, evidence);
            Assert(args.Contains("-x") && args.Contains("--audio-format"), "audio " + container);
        }
        foreach (var video in DownloadCommand.VideoCodecs)
        foreach (var audio in DownloadCommand.AudioCodecs)
        {
            var selected = options with { VideoCodec = video, AudioCodec = audio, Resolution = "1080", Fps = "60" };
            var selector = DownloadCommand.Selector(selected);
            var fallback = selector.Split('/')[1];
            Assert(fallback.Contains("[height<=1080]") && fallback.Contains("[fps<=60]"), "fallback resolution/fps");
            Assert(video == "any" || fallback.Contains(DownloadCommand.CodecFilter(video, true)), "no silent video fallback");
            Assert(audio == "any" || fallback.Contains(DownloadCommand.CodecFilter(audio, false)), "no silent audio fallback");
        }
        foreach (var quality in new[] { "0", "5", "10", "320K", "128k" })
            Assert(DownloadCommand.Arguments("https://example.test", options with { Kind = MediaKind.Audio, Container = "ogg", AudioQuality = quality }).Contains(quality), "quality accepts " + quality);
        foreach (var quality in new[] { "-1", "11", "NaN", "0K", "320K;bad", "" })
            Throws<ArgumentException>(() => DownloadCommand.Arguments("https://example.test", options with { AudioQuality = quality }));
        Assert(DownloadCommand.CodecFilter("h264", true).Contains("avc|h264"), "avc aliases");
        Assert(DownloadCommand.CodecFilter("aac", false).Contains("mp4a|aac"), "aac aliases");
        const string hostileUrl = "https://example.test/a?x=$(touch%20oops);&y=\"%20--exec=bad";
        const string hostileSelector = "best; $(touch injected) & --exec=bad";
        var hostile = DownloadCommand.Arguments(hostileUrl, options with { Selector = hostileSelector }, evidence);
        Assert(hostile[^2] == "--" && hostile[^1] == hostileUrl && hostile.Contains(hostileSelector), "URL guard and opaque selector");
        var start = DownloadCommand.StartInfo("/fake tool", hostile, evidence);
        Assert(!start.UseShellExecute && start.CreateNoWindow && start.Arguments.Length == 0 && start.ArgumentList.SequenceEqual(hostile), "safe ArgumentList");
        Assert(start.RedirectStandardError && start.RedirectStandardOutput, "both redirected");
        Assert(hostile.Contains("--ignore-config") && hostile.Contains("--no-playlist") && hostile.Contains("--windows-filenames"), "required safety flags");
        Assert(new DownloadService().ToolDirectory == Path.Combine(AppContext.BaseDirectory, "tools"), "bundled tools root");
        Assert(hostile.Contains("deno:" + Path.Combine(evidence, OperatingSystem.IsWindows() ? "deno.exe" : "deno")), "absolute deno");
        foreach (var bad in new[] { "file:///etc/passwd", "ftp://example.test/a", "--exec=bad", "https://x\n--exec=bad", "", "http://" })
            Throws<ArgumentException>(() => DownloadCommand.ValidateUrl(bad));
        Throws<ArgumentException>(() => DownloadCommand.Selector(options with { VideoCodec = "h264;touch" }));
        Throws<ArgumentException>(() => DownloadCommand.Selector(options with { Fps = "30][exec=evil" }));
        Throws<ArgumentException>(() => DownloadCommand.Arguments("https://example.test", options with { AudioQuality = "--exec=bad" }));
        Throws<ArgumentException>(() => DownloadCommand.Arguments("https://example.test", options with { Container = "bad" }));
        var progress = DownloadOutputParser.Parse("STUDIO_PROGRESS: 42.5%| 1.2MiB/s| 00:20")!;
        Assert(progress.Progress == 42.5 && progress.Speed == "1.2MiB/s" && progress.Eta == "00:20", "progress fields");
        Assert(DownloadOutputParser.Parse("STUDIO_PROGRESS:100%|N/A|N/A") is { Status: "Finalizando", Speed: "", Eta: "" }, "100 means finalizing");
        Assert(DownloadOutputParser.Parse("STUDIO_PROGRESS:NaN|N/A|N/A")?.Progress is null, "NaN is not progress");
        Assert(DownloadOutputParser.Parse("STUDIO_TITLE:Olá mundo")?.Title == "Olá mundo", "Unicode title");
        Assert(DownloadOutputParser.Parse("ERROR: missing codec")?.Error == "missing codec", "visible errors");
        using var json = JsonDocument.Parse("""{"format_id":"137","ext":"mp4","height":1080,"vcodec":"avc1","acodec":"none","filesize":1048576} """);
        using var nullJson = JsonDocument.Parse("""{"format_id":"a","vcodec":"none","acodec":"aac","height":null,"filesize":null,"filesize_approx":1234}""");
        Assert(SourceFormat.Parse(nullJson.RootElement) is { FileSize: 1234, HasVideo: false }, "nullable JSON numbers");
        var format = SourceFormat.Parse(json.RootElement)!;
        Assert(format.Selector == "137+ba" && format.HasVideo && !format.HasAudio && format.SizeLabel == "1.0 MiB", "source format");
    }
    private static async Task ProcessTests(string evidence)
    {
        var tools = Path.Combine(evidence, "fake tools ç"); Directory.CreateDirectory(tools);
        foreach (var file in Directory.EnumerateFiles(AppContext.BaseDirectory)) File.Copy(file, Path.Combine(tools, Path.GetFileName(file)), true);
        var self = Environment.ProcessPath!;
        if (Path.GetFileNameWithoutExtension(self) == "dotnet") throw new Exception("Run via dotnet run (apphost required for process fixtures).");
        foreach (var name in new[] { "yt-dlp", "ffmpeg", "ffprobe", "deno" })
        {
            var target = DownloadCommand.ToolPath(tools, name); File.Copy(self, target, true);
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(target, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
        var service = new DownloadService(tools);
        var childFile = Path.Combine(evidence, "child.pid");
        Environment.SetEnvironmentVariable("STUDIO_TEST_CHILD", childFile);
        try
        {
            Environment.SetEnvironmentVariable("STUDIO_TEST_FAKE", "probe-ok");
            var probe = await service.ProbeAsync("https://example.test");
            Assert(probe.Title == "Título ç" && probe.Formats.Count == 1, "probe process parses");
            Environment.SetEnvironmentVariable("STUDIO_TEST_FAKE", "probe-error");
            var ex = await ThrowsAsync<DownloadException>(() => service.ProbeAsync("https://example.test"));
            Assert(ex.ExitCode == 7 && ex.ErrorReport.Contains("probe denied"), "probe exit failure");
            Environment.SetEnvironmentVariable("STUDIO_TEST_FAKE", "probe-invalid");
            await ThrowsAsync<DownloadException>(() => service.ProbeAsync("https://example.test"));
            Environment.SetEnvironmentVariable("STUDIO_TEST_FAKE", "probe-oversized");
            var oversized = await ThrowsAsync<DownloadException>(() => service.ProbeAsync("https://example.test"));
            Assert(oversized.ErrorReport.Length <= 32768 && oversized.Message.Contains("16 MiB"), "bounded probe JSON and logs");
            Environment.SetEnvironmentVariable("STUDIO_TEST_FAKE", "probe-empty");
            await ThrowsAsync<DownloadException>(() => service.ProbeAsync("https://example.test"));
            var updates = new List<DownloadUpdate>();
            var destination = Path.Combine(evidence, "download ç espaço");
            Environment.SetEnvironmentVariable("STUDIO_TEST_FAKE", "download-ok");
            var downloaded = await service.RunAsync("https://example.test", new(), destination, updates.Add);
            Assert(File.Exists(downloaded.Path) && downloaded.Title == "Título ç" && updates[^1].Status == "Concluído", "download success exists Unicode path");
            foreach (var mode in new[] { "download-missing", "download-exit", "download-no-marker", "download-error-zero" })
            {
                Environment.SetEnvironmentVariable("STUDIO_TEST_FAKE", mode); updates.Clear();
                var failed = await ThrowsAsync<DownloadException>(() => service.RunAsync("https://example.test", new(), destination, updates.Add));
                Assert(failed.ExitCode != 0 && updates.All(u => u.Status != "Concluído") && updates[^1].Error is not null, "no false complete " + mode);
                Assert(failed.ErrorReport.Length <= 32768, "bounded logs");
            }
            foreach (var isProbe in new[] { true, false })
            {
                if (File.Exists(childFile)) File.Delete(childFile);
                Environment.SetEnvironmentVariable("STUDIO_TEST_FAKE", "cancel");
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                var operation = isProbe ? (Task)service.ProbeAsync("https://example.test", cts.Token) : service.RunAsync("https://example.test", new(), destination, _ => { }, cts.Token);
                for (var i = 0; i < 100 && !File.Exists(childFile); i++) await Task.Delay(50);
                Assert(File.Exists(childFile), "child started"); var pid = int.Parse(File.ReadAllText(childFile));
                cts.Cancel(); await ThrowsAsync<OperationCanceledException>(() => operation.WaitAsync(TimeSpan.FromSeconds(8)));
                await Task.Delay(100);
                bool dead; try { using var child = Process.GetProcessById(pid); dead = child.HasExited; } catch (ArgumentException) { dead = true; }
                Assert(dead, "ffmpeg process tree killed " + isProbe);
            }
        }
        finally { Environment.SetEnvironmentVariable("STUDIO_TEST_FAKE", null); Environment.SetEnvironmentVariable("STUDIO_TEST_CHILD", null); }
    }
    private static async Task<int> Fake(string mode, string[] args)
    {
        if (mode == "cancel")
        {
            var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
            start.ArgumentList.Add("--fake-child"); using var child = Process.Start(start)!;
            await Task.Delay(Timeout.Infinite); return 0;
        }
        if (mode == "probe-error") { Console.Error.WriteLine("ERROR: probe denied"); return 7; }
        if (mode == "probe-invalid") { Console.WriteLine("not json"); return 0; }
        if (mode == "probe-oversized") { var block = new string('x', 4096); for (var i = 0; i < 4097; i++) Console.Write(block); return 0; }
        if (mode == "probe-empty") { Console.WriteLine("{}"); return 0; }
        if (mode == "probe-ok") { Console.WriteLine("""{"title":"Título ç","formats":[{"format_id":"1","ext":"mp4","vcodec":"h264","acodec":"aac"}]}"""); return 0; }
        Console.WriteLine("STUDIO_TITLE:Título ç");
        Console.WriteLine("STUDIO_PROGRESS:100%|N/A|N/A");
        if (mode == "download-exit")
        {
            var huge = new string('x', 4096);
            await Task.WhenAll(Task.Run(() => { for (var i = 0; i < 200; i++) Console.Out.WriteLine(huge); }), Task.Run(() => { for (var i = 0; i < 200; i++) Console.Error.WriteLine(huge); }));
            Console.Error.WriteLine("ERROR: unsupported codec"); return 9;
        }
        if (mode == "download-error-zero") { Console.Error.WriteLine("ERROR: postprocessing failed"); return 0; }
        if (mode == "download-no-marker") return 0;
        var path = Path.Combine(Environment.CurrentDirectory, "vídeo espaço.mp4");
        if (mode == "download-ok") File.WriteAllText(path, "fixture");
        if (mode == "download-missing") path += ".missing";
        Console.WriteLine("STUDIO_FILE:" + path); return 0;
    }
    private static async Task<(int Code, string Output)> RunTool(string executable, params string[] args)
    {
        using var process = new Process { StartInfo = DownloadCommand.StartInfo(executable, args, Environment.CurrentDirectory) };
        process.Start(); var stdout = process.StandardOutput.ReadToEndAsync(); var stderr = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync(); return (process.ExitCode, await stdout + await stderr);
    }
    private static async Task Integration(string tools, string evidence)
    {
        var fixture = Path.Combine(evidence, "fixture.wav");
        var generated = await RunTool(DownloadCommand.ToolPath(tools, "ffmpeg"), "-nostdin", "-hide_banner", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4", "-ac", "2", fixture);
        Assert(generated.Code == 0, "generate real audio fixture: " + generated.Output);
        var data = File.ReadAllBytes(fixture);
        using var server = new FixtureServer(data);
        var service = new DownloadService(tools);
        var probe = await service.ProbeAsync(server.Url);
        Assert(probe.Formats.Count > 0, "real local HTTP probe");
        var results = new List<object>();
        var expected = new Dictionary<string, string> { ["best"] = "pcm_s16le", ["mp3"] = "mp3", ["m4a"] = "aac", ["aac"] = "aac", ["opus"] = "opus", ["vorbis"] = "vorbis", ["flac"] = "flac", ["alac"] = "alac", ["wav"] = "pcm_s16le", ["aiff"] = "pcm_s16be", ["mka"] = "pcm_s16le", ["ogg"] = "vorbis" };
        foreach (var container in DownloadCommand.AudioContainers)
        {
            var updates = new List<DownloadUpdate>();
            var downloaded = await service.RunAsync(server.Url, new() { Kind = MediaKind.Audio, Container = container }, Path.Combine(evidence, "áudio " + container), updates.Add);
            var inspected = await RunTool(DownloadCommand.ToolPath(tools, "ffprobe"), "-v", "error", "-show_entries", "stream=codec_name,codec_type", "-show_entries", "format=format_name,duration", "-of", "json", downloaded.Path);
            File.WriteAllText(Path.Combine(evidence, container + "-ffprobe.json"), inspected.Output);
            Assert(inspected.Code == 0, "ffprobe " + container);
            using var json = JsonDocument.Parse(inspected.Output);
            var streams = json.RootElement.GetProperty("streams").EnumerateArray().ToArray();
            Assert(streams.Length == 1 && streams[0].GetProperty("codec_type").GetString() == "audio", "audio only " + container);
            Assert(streams[0].GetProperty("codec_name").GetString() == expected[container], "actual codec " + container);
            Assert(updates[^1].Status == "Concluído" && new FileInfo(downloaded.Path).Length > 0, "real complete " + container);
            results.Add(new { Container = container, downloaded.Path, downloaded.Title });
            Console.WriteLine("PASS real audio " + container);
        }
        var bitrateResult = await service.RunAsync(server.Url, new() { Kind = MediaKind.Audio, Container = "ogg", AudioQuality = "128K" }, Path.Combine(evidence, "ogg bitrate"), _ => { });
        Assert(File.Exists(bitrateResult.Path), "OGG bitrate conversion");
        File.WriteAllText(Path.Combine(evidence, "audio-results.json"), JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
    }
    private sealed class FixtureServer : IDisposable
    {
        private readonly TcpListener listener = new(IPAddress.Loopback, 0);
        private readonly CancellationTokenSource stop = new();
        public string Url { get; }
        public FixtureServer(byte[] data)
        {
            listener.Start(); Url = $"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/fixture.wav";
            _ = Task.Run(async () =>
            {
                try
                {
                    while (!stop.IsCancellationRequested)
                    {
                        var client = await listener.AcceptTcpClientAsync(stop.Token);
                        _ = Task.Run(async () =>
                        {
                            using (client)
                            {
                                try
                                {
                                    var stream = client.GetStream(); using var reader = new StreamReader(stream, Encoding.ASCII, false, 1024, true);
                                    var request = await reader.ReadLineAsync(); while (await reader.ReadLineAsync() is { Length: > 0 }) { }
                                    var header = Encoding.ASCII.GetBytes($"HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nContent-Length: {data.Length}\r\nConnection: close\r\n\r\n");
                                    await stream.WriteAsync(header); if (request?.StartsWith("HEAD ") != true) await stream.WriteAsync(data);
                                }
                                catch (IOException) { }
                            }
                        });
                    }
                }
                catch (OperationCanceledException) { }
                catch (SocketException) when (stop.IsCancellationRequested) { }
            });
        }
        public void Dispose() { stop.Cancel(); listener.Stop(); stop.Dispose(); }
    }
}
