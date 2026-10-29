using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace YTDLPStudio.Core;

/// <summary>Callbacks are serialized and may run on any thread. UI callers must dispatch updates to their UI thread.</summary>
public sealed class DownloadService
{
    public string ToolDirectory { get; }
    public DownloadService(string? toolDirectory = null) => ToolDirectory = Path.GetFullPath(toolDirectory ?? Path.Combine(AppContext.BaseDirectory, "tools"));
    private string Tool(string name)
    {
        var path = DownloadCommand.ToolPath(ToolDirectory, name);
        if (!File.Exists(path)) throw new DownloadException($"Ferramenta ausente: {path}. Reinstale o pacote completo do YTDLP Studio.");
        return path;
    }
    public async Task<DownloadResult> RunAsync(string url, DownloadOptions options, string directory, Action<DownloadUpdate> onUpdate, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(onUpdate);
        var args = DownloadCommand.Arguments(url, options, ToolDirectory);
        token.ThrowIfCancellationRequested();
        string title = "", finalPath = "", lastError = "";
        var callbackLock = new object();
        void Notify(DownloadUpdate update) { lock (callbackLock) onUpdate(update); }
        try
        {
            var executable = Tool("yt-dlp"); _ = Tool("ffmpeg"); _ = Tool("ffprobe"); _ = Tool("deno");
            directory = Path.GetFullPath(directory); Directory.CreateDirectory(directory);
            Notify(new(Status: "Preparando"));
            var run = await ExecuteAsync(DownloadCommand.StartInfo(executable, args, directory), line =>
            {
                lock (callbackLock)
                {
                    if (line.StartsWith("STUDIO_FILE:", StringComparison.Ordinal))
                    {
                        try { finalPath = JsonSerializer.Deserialize<string>(line[12..]) ?? ""; }
                        catch (JsonException) { lastError = "O yt-dlp informou um caminho final inválido."; }
                    }
                    if (DownloadOutputParser.Parse(line) is { } update)
                    {
                        if (update.Title is not null) title = update.Title;
                        if (update.Error is not null) lastError = update.Error;
                        onUpdate(update);
                    }
                }
            }, false, token).ConfigureAwait(false);
            if (run.ExitCode != 0) throw Failure("O download falhou. Verifique o link, o formato e os codecs selecionados.", run, lastError);
            if (lastError.Length != 0) throw Failure("O download relatou um erro: " + lastError, run, lastError);
            if (string.IsNullOrWhiteSpace(finalPath)) throw Failure("O processo terminou sem informar o arquivo final.", run);
            finalPath = Path.GetFullPath(finalPath, directory);
            if (!File.Exists(finalPath)) throw Failure("O arquivo final não foi encontrado: " + finalPath, run);
            if (options.Kind == MediaKind.Audio && options.Container is "aiff" or "mka" or "ogg")
            {
                Notify(new(Status: "Finalizando"));
                finalPath = await ConvertExtraAudioAsync(finalPath, options, token).ConfigureAwait(false);
            }
            token.ThrowIfCancellationRequested();
            if (!File.Exists(finalPath)) throw new DownloadException("O arquivo final não foi encontrado: " + finalPath);
            if (title.Length == 0) title = Path.GetFileNameWithoutExtension(finalPath);
            Notify(new(Title: title, Progress: 100, Status: "Concluído"));
            return new(finalPath, title);
        }
        catch (OperationCanceledException) { Notify(new(Status: "Cancelado")); throw; }
        catch (Exception ex)
        {
            var error = ex as DownloadException ?? new DownloadException("Não foi possível baixar: " + ex.Message, inner: ex);
            Notify(new(Status: "Falhou", Error: error.Message)); throw error;
        }
    }
    private async Task<string> ConvertExtraAudioAsync(string source, DownloadOptions options, CancellationToken token)
    {
        var destination = Path.ChangeExtension(source, options.Container);
        // Always use a unique intermediate file; never truncate a source or an existing user file.
        var temporary = Path.Combine(Path.GetDirectoryName(source)!, ".studio-" + Guid.NewGuid().ToString("N") + "." + options.Container);
        var args = new List<string> { "-nostdin", "-hide_banner", "-n", "-i", source, "-map", "0:a:0", "-vn" };
        args.AddRange(options.Container switch
        {
            "aiff" => new[] { "-c:a", "pcm_s16be" },
            "mka" => new[] { "-c:a", "copy" },
            "ogg" => DownloadCommand.IsBitrate(options.AudioQuality)
                ? new[] { "-c:a", "libvorbis", "-b:a", options.AudioQuality }
                : new[] { "-c:a", "libvorbis", "-q:a", Math.Clamp(10m - decimal.Parse(options.AudioQuality, System.Globalization.CultureInfo.InvariantCulture), -1m, 10m).ToString(System.Globalization.CultureInfo.InvariantCulture) },
            _ => throw new ArgumentException("Formato de áudio desconhecido.")
        });
        args.Add(temporary);
        try
        {
            var run = await ExecuteAsync(DownloadCommand.StartInfo(Tool("ffmpeg"), args, Path.GetDirectoryName(source)!), null, false, token).ConfigureAwait(false);
            if (run.ExitCode != 0 || !File.Exists(temporary)) throw Failure("A conversão de áudio falhou. Confira o suporte do FFmpeg ao codec selecionado.", run);
            token.ThrowIfCancellationRequested();
            // Existing destinations cause an explicit error, rather than false completion.
            File.Move(temporary, destination, false);
            return destination;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    public async Task<ProbeResult> ProbeAsync(string url, CancellationToken token = default)
    {
        DownloadCommand.ValidateUrl(url); token.ThrowIfCancellationRequested();
        var args = DownloadCommand.CommonArguments(ToolDirectory);
        args.AddRange(new[] { "--dump-single-json", "--skip-download", "--no-warnings", "--socket-timeout", "15", "--", url });
        var run = await ExecuteAsync(DownloadCommand.StartInfo(Tool("yt-dlp"), args, ToolDirectory), null, true, token).ConfigureAwait(false);
        if (run.ExitCode != 0) throw Failure("Não foi possível consultar os formatos. Verifique o link e tente novamente.", run);
        if (run.OutputOverflow) throw Failure("A lista de formatos excedeu o limite de 16 MiB.", run);
        try
        {
            using var json = JsonDocument.Parse(run.Output);
            var root = json.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw Failure("A ferramenta retornou uma lista de formatos inválida.", run);
            var formats = root.TryGetProperty("formats", out var values) && values.ValueKind == JsonValueKind.Array
                ? values.EnumerateArray().Select(SourceFormat.Parse).OfType<SourceFormat>().Reverse().ToArray() : Array.Empty<SourceFormat>();
            if (formats.Length == 0) throw Failure("Nenhum formato de áudio ou vídeo foi encontrado.", run);
            var title = root.TryGetProperty("title", out var t) && t.ValueKind == JsonValueKind.String ? t.GetString() ?? "Formatos disponíveis" : "Formatos disponíveis";
            return new(title, Array.AsReadOnly(formats));
        }
        catch (JsonException ex) { throw new DownloadException("A ferramenta retornou uma lista de formatos inválida.", -1, run.Log, ex); }
    }
    private static DownloadException Failure(string message, ProcessResult run, string detail = "")
        => new(message + (detail.Length == 0 ? "" : " " + detail) + (run.ExitCode == 0 ? "" : $" (código {run.ExitCode})"), run.ExitCode, run.Log);
    private sealed record ProcessResult(int ExitCode, string Output, bool OutputOverflow, string Log);
    private static async Task<ProcessResult> ExecuteAsync(ProcessStartInfo start, Action<string>? consume, bool capture, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        using var process = new Process { StartInfo = start };
        try { process.Start(); }
        catch (Exception ex) { throw new DownloadException("Não foi possível iniciar " + Path.GetFileName(start.FileName) + ": " + ex.Message, inner: ex); }
        void Kill() { try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { } catch (System.ComponentModel.Win32Exception) { } }
        using var registration = token.Register(Kill);
        var log = new StringBuilder(); var output = new StringBuilder(); var gate = new object(); var overflow = false;
        const int maxLog = 32768, maxOutput = 16 * 1024 * 1024, maxLine = 16384;
        async Task Drain(StreamReader reader, bool stdout)
        {
            var buffer = new char[4096]; var line = new StringBuilder();
            try
            {
                int count;
                while ((count = await reader.ReadAsync(buffer.AsMemory()).ConfigureAwait(false)) > 0)
                {
                    lock (gate)
                    {
                        log.Append(buffer, 0, count); if (log.Length > maxLog) log.Remove(0, log.Length - maxLog);
                        if (capture && stdout)
                        {
                            var available = maxOutput - output.Length;
                            output.Append(buffer, 0, Math.Min(available, count)); if (count > available) overflow = true;
                        }
                    }
                    if (consume is null) continue;
                    for (var i = 0; i < count; i++)
                    {
                        var ch = buffer[i];
                        if (ch is '\n' or '\r') { if (line.Length > 0) { consume(line.ToString()); line.Clear(); } }
                        else if (line.Length < maxLine) line.Append(ch);
                    }
                }
                if (line.Length > 0) consume?.Invoke(line.ToString());
            }
            catch { Kill(); throw; }
        }
        var stdoutTask = Drain(process.StandardOutput, true);
        var stderrTask = Drain(process.StandardError, false);
        try
        {
            await Task.WhenAll(stdoutTask, stderrTask, process.WaitForExitAsync(CancellationToken.None)).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            return new(process.ExitCode, output.ToString(), overflow, log.ToString());
        }
        catch { Kill(); throw; }
    }
}
