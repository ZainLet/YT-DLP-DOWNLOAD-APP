using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;

namespace YTDLPStudio.Core;

public static class DownloadCommand
{
    public static IReadOnlyList<string> VideoContainers { get; } = Array.AsReadOnly(new[] { "auto", "mp4", "mkv", "webm", "mov", "avi", "flv", "gif" });
    public static IReadOnlyList<string> AudioContainers { get; } = Array.AsReadOnly(new[] { "best", "mp3", "m4a", "aac", "opus", "vorbis", "flac", "alac", "wav", "aiff", "mka", "ogg" });
    public static IReadOnlyList<string> VideoCodecs { get; } = Array.AsReadOnly(new[] { "any", "h264", "hevc", "av1", "vp9", "vp8", "mpeg4", "mpeg2", "theora", "prores" });
    public static IReadOnlyList<string> AudioCodecs { get; } = Array.AsReadOnly(new[] { "any", "aac", "opus", "vorbis", "mp3", "flac", "alac", "pcm", "ac3", "eac3", "dts" });
    public static string ValidateUrl(string url)
    {
        if (string.IsNullOrWhiteSpace(url) || url.Any(char.IsControl) || !Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) || string.IsNullOrEmpty(uri.Host))
            throw new ArgumentException("Informe um link HTTP ou HTTPS válido.", nameof(url));
        return url;
    }
    public static string CodecFilter(string codec, bool video)
    {
        if (!(video ? VideoCodecs : AudioCodecs).Contains(codec)) throw new ArgumentException("Codec desconhecido: " + codec);
        if (codec == "any") return "";
        var alias = codec switch { "h264" => "avc|h264", "hevc" => "hev|hvc|hevc|h265", "av1" => "av01|av1", "vp9" => "vp09|vp9", "vp8" => "vp08|vp8", "aac" => "mp4a|aac", _ => codec };
        return $"[{(video ? "vcodec" : "acodec")}~='^({alias})']";
    }
    public static string Selector(DownloadOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        var v = CodecFilter(options.VideoCodec, true); var a = CodecFilter(options.AudioCodec, false);
        if (options.Resolution != "best") { PositiveNumber(options.Resolution, "Resolução"); v += $"[height<={options.Resolution}]"; }
        if (options.Fps != "any") { PositiveNumber(options.Fps, "FPS"); v += $"[fps<={options.Fps}]"; }
        if (!string.IsNullOrWhiteSpace(options.Selector))
        {
            if (options.Selector.Length > 4096 || options.Selector.Any(char.IsControl)) throw new ArgumentException("Seletor de formato inválido.");
            return options.Selector;
        }
        return options.Kind == MediaKind.Audio ? $"ba{a}/b{a}" : $"bv{v}+ba{a}/b{v}{a}";
    }
    internal static bool IsBitrate(string value) => value.Length > 1 && value[^1] is 'K' or 'k' &&
        int.TryParse(value[..^1], NumberStyles.None, CultureInfo.InvariantCulture, out var rate) && rate > 0;
    internal static void ValidateAudioQuality(string value)
    {
        if (string.IsNullOrEmpty(value) || (!IsBitrate(value) &&
            (!decimal.TryParse(value, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var quality) || quality < 0 || quality > 10)))
            throw new ArgumentException("Qualidade de áudio deve estar entre 0 e 10 ou ser um bitrate como 320K.");
    }
    private static void PositiveNumber(string value, string name)
    {
        if (!decimal.TryParse(value, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var n) || n <= 0) throw new ArgumentException(name + " inválido.");
    }
    internal static string ToolPath(string directory, string name) => Path.Combine(Path.GetFullPath(directory), name + (OperatingSystem.IsWindows() ? ".exe" : ""));
    internal static List<string> CommonArguments(string toolDirectory) => new() { "--ignore-config", "--no-playlist", "--windows-filenames", "--no-color", "--ffmpeg-location", Path.GetFullPath(toolDirectory), "--js-runtimes", "deno:" + ToolPath(toolDirectory, "deno") };
    public static IReadOnlyList<string> Arguments(string url, DownloadOptions options, string? toolDirectory = null)
    {
        ValidateUrl(url); var selector = Selector(options);
        if (!Enum.IsDefined(options.Kind) || !(options.Kind == MediaKind.Video ? VideoContainers : AudioContainers).Contains(options.Container)) throw new ArgumentException("Contêiner inválido para o tipo de mídia.");
        ValidateAudioQuality(options.AudioQuality);
        var args = CommonArguments(toolDirectory ?? Path.Combine(AppContext.BaseDirectory, "tools"));
        args.AddRange(new[] { "--newline", "--no-overwrites", "--progress", "--progress-template", "download:STUDIO_PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s", "--print", "before_dl:STUDIO_TITLE:%(title)s", "--print", "after_move:STUDIO_FILE:%(filepath)j", "--no-simulate", "-o", "%(title).180s [%(id)s].%(ext)s", "-f", selector });
        if (options.Kind == MediaKind.Audio)
            args.AddRange(new[] { "-x", "--audio-format", options.Container is "aiff" or "mka" or "ogg" ? "best" : options.Container, "--audio-quality", options.AudioQuality });
        else if (options.Container != "auto") args.AddRange(new[] { "--remux-video", options.Container });
        args.AddRange(new[] { "--", url }); return args.AsReadOnly();
    }
    internal static ProcessStartInfo StartInfo(string executable, IEnumerable<string> args, string directory)
    {
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = directory,
            StandardOutputEncoding = System.Text.Encoding.UTF8, StandardErrorEncoding = System.Text.Encoding.UTF8 };
        foreach (var arg in args) start.ArgumentList.Add(arg);
        start.Environment["DENO_NO_UPDATE_CHECK"] = "1";
        start.Environment["PYTHONIOENCODING"] = "utf-8";
        return start;
    }
}
