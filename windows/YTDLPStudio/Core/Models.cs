using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json;

namespace YTDLPStudio.Core;

public enum MediaKind { Video, Audio }
public sealed record DownloadOptions
{
    public MediaKind Kind { get; init; } = MediaKind.Video;
    public string Container { get; init; } = "mp4";
    public string Resolution { get; init; } = "best";
    public string VideoCodec { get; init; } = "any";
    public string AudioCodec { get; init; } = "any";
    public string AudioQuality { get; init; } = "0";
    public string Fps { get; init; } = "any";
    public string Selector { get; init; } = "";
}
public sealed record DownloadUpdate(string? Title = null, double? Progress = null,
    string? Speed = null, string? Eta = null, string? Status = null, string? Error = null);
public sealed record DownloadResult(string Path, string Title);
public sealed record ProbeResult(string Title, IReadOnlyList<SourceFormat> Formats);
public sealed class DownloadException : Exception
{
    public int ExitCode { get; }
    public string ErrorReport { get; }
    public DownloadException(string message, int exitCode = -1, string errorReport = "", Exception? inner = null)
        : base(message, inner) { ExitCode = exitCode == 0 ? -1 : exitCode; ErrorReport = errorReport; }
}
public sealed record SourceFormat(string Id, string Extension, string Resolution,
    string VideoCodec, string AudioCodec, string Detail, double? FileSize = null)
{
    public bool HasVideo => VideoCodec is not ("none" or "");
    public bool HasAudio => AudioCodec is not ("none" or "");
    public string Selector => HasVideo && !HasAudio ? Id + "+ba" : Id;
    public string SizeLabel => FileSize is > 0 ? (FileSize / 1048576d)?.ToString("0.0", CultureInfo.InvariantCulture) + " MiB" : "—";
    public static SourceFormat? Parse(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object) return null;
        string Get(string key, string fallback = "") => value.TryGetProperty(key, out var p) && p.ValueKind == JsonValueKind.String ? p.GetString() ?? fallback : fallback;
        double? Number(string key) => value.TryGetProperty(key, out var p) && p.ValueKind == JsonValueKind.Number && p.TryGetDouble(out var n) ? n : null;
        var id = Get("format_id"); var video = Get("vcodec", "unknown"); var audio = Get("acodec", "unknown");
        if (id.Length == 0 || (video == "none" && audio == "none")) return null;
        return new(id, Get("ext", "—"), Get("resolution", Number("height") is { } h ? $"{h}p" : video == "none" ? "Somente áudio" : "Não informada"),
            video, audio, Get("format_note"), Number("filesize") ?? Number("filesize_approx"));
    }
}
public static class DownloadOutputParser
{
    public static DownloadUpdate? Parse(string line)
    {
        if (line.StartsWith("STUDIO_TITLE:", StringComparison.Ordinal)) return new(Title: line[13..]);
        if (line.StartsWith("STUDIO_PROGRESS:", StringComparison.Ordinal))
        {
            var fields = line[16..].Split('|');
            double? percent = double.TryParse(fields[0].Trim().TrimEnd('%'), NumberStyles.Float, CultureInfo.InvariantCulture, out var p) && double.IsFinite(p) ? Math.Clamp(p, 0, 100) : null;
            string Field(int i) => fields.Length > i && fields[i].Trim() != "N/A" ? fields[i].Trim() : "";
            return new(Progress: percent, Speed: Field(1), Eta: Field(2), Status: percent >= 100 ? "Finalizando" : "Baixando");
        }
        var error = line.IndexOf("ERROR:", StringComparison.Ordinal);
        return error >= 0 ? new(Status: "Falhou", Error: line[(error + 6)..].Trim()) : null;
    }
}
