using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using YTDLPStudio.Core;

namespace YTDLPStudio;

public class Observable : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected void Changed([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    { if (EqualityComparer<T>.Default.Equals(field, value)) return false; field = value; Changed(name); return true; }
}

public sealed class StudioJob : Observable
{
    public string Url { get; }
    public DownloadOptions Options { get; }
    public string Directory { get; }
    public CancellationTokenSource Cancellation { get; } = new();
    public bool IsRunning { get; internal set; }
    private string title = "", status = "Na fila", speed = "", eta = "", error = "", file = "";
    private double progress;
    public string Title { get => title; set { Set(ref title, value); Changed(nameof(DisplayTitle)); } }
    public string Status { get => status; set { Set(ref status, value); Refresh(); } }
    public string Speed { get => speed; set { Set(ref speed, value); Changed(nameof(Detail)); } }
    public string Eta { get => eta; set { Set(ref eta, value); Changed(nameof(Detail)); } }
    public string Error { get => error; set => Set(ref error, value); }
    public string File { get => file; set { Set(ref file, value); Changed(nameof(RevealVisibility)); } }
    public double Progress { get => progress; set { Set(ref progress, value); Changed(nameof(Detail)); } }
    public string DisplayTitle => Title.Length > 0 ? Title : Url;
    public string Detail => string.Join(" · ", new[] { Status, Options.Kind == MediaKind.Audio ? "Áudio" : "Vídeo", Options.Container.ToUpperInvariant(),
        Status is "Baixando" or "Finalizando" ? $"{Progress:0}%" : "", Speed, Eta.Length > 0 ? "Restante: " + Eta : "" }.Where(x => x.Length > 0));
    public Visibility CancelVisibility => Status == "Na fila" || IsRunning ? Visibility.Visible : Visibility.Collapsed;
    public Visibility RevealVisibility => Status == "Concluído" && File.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    public Visibility RetryVisibility => Status is "Falhou" or "Cancelado" && !IsRunning ? Visibility.Visible : Visibility.Collapsed;
    public Visibility ProgressVisibility => IsRunning ? Visibility.Visible : Visibility.Collapsed;
    public StudioJob(string url, DownloadOptions options, string directory) { Url = url; Options = options; Directory = directory; }
    internal void Refresh() { foreach (var p in new[] { nameof(Detail), nameof(CancelVisibility), nameof(RevealVisibility), nameof(RetryVisibility), nameof(ProgressVisibility) }) Changed(p); }
}

public sealed record Choice(string Value, string Label);

public sealed class StudioViewModel : Observable
{
    private readonly DownloadService service;
    public ObservableCollection<StudioJob> Jobs { get; } = new();
    private bool stopping;
    private string links = "", directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "YTDLP Studio");
    private MediaKind kind = MediaKind.Video;
    private string container = "mp4", resolution = "best", audioQuality = "0", videoCodec = "any", audioCodec = "any", fps = "any", selector = "", filter = "Todos";
    public StudioViewModel(DownloadService? service = null) => this.service = service ?? new();
    public string Links { get => links; set { if (Set(ref links, value)) UpdateInput(); } }
    public string Directory { get => directory; set { if (Set(ref directory, value)) UpdateInput(); } }
    public MediaKind Kind { get => kind; set { if (Set(ref kind, value)) { Container = value == MediaKind.Video ? "mp4" : "mp3"; Selector = ""; Changed(nameof(Containers)); Changed(nameof(VideoVisibility)); Changed(nameof(AudioVisibility)); } } }
    public string Container { get => container; set { if (value is not null) Set(ref container, value); } }
    public string Resolution { get => resolution; set { if (value is not null) Set(ref resolution, value); } }
    public string AudioQuality { get => audioQuality; set { if (value is not null) Set(ref audioQuality, value); } }
    public string VideoCodec { get => videoCodec; set { if (value is not null) Set(ref videoCodec, value); } }
    public string AudioCodec { get => audioCodec; set { if (value is not null) Set(ref audioCodec, value); } }
    public string Fps { get => fps; set { if (value is not null) Set(ref fps, value); } }
    public string Selector { get => selector; set => Set(ref selector, value); }
    public string Filter { get => filter; set { Set(ref filter, value); Changed(nameof(ActivityJobs)); Changed(nameof(ActivityEmpty)); } }
    public string[] Filters { get; } = ["Todos", "Baixando", "Na fila", "Falhas", "Cancelados"];
    public string[] LinkList => Links.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    public string LinkCountLabel => LinkList.Length == 0 ? "Um por linha" : $"{LinkList.Length} {(LinkList.Length == 1 ? "link" : "links")}";
    public Visibility PlaceholderVisibility => Links.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
    public bool CanProbe => LinkList.Length > 0 && LinkList.All(ValidUrl);
    public bool CanAdd => CanProbe && !string.IsNullOrWhiteSpace(Directory) && !stopping;
    public string ValidationError => LinkList.Any(x => !ValidUrl(x)) ? "Use links completos começando com https:// ou http://" : "";
    public string DownloadButtonLabel => LinkList.Length > 1 ? $"Baixar {LinkList.Length} arquivos" : "Iniciar download";
    public Visibility VideoVisibility => Kind == MediaKind.Video ? Visibility.Visible : Visibility.Collapsed;
    public Visibility AudioVisibility => Kind == MediaKind.Audio ? Visibility.Visible : Visibility.Collapsed;
    public int ActiveCount => Jobs.Count(x => x.IsRunning);
    public int QueuedCount => Jobs.Count(x => x.Status == "Na fila");
    public int DoneCount => Jobs.Count(x => x.Status == "Concluído");
    public bool ActivityEmpty => !ActivityJobs.Any();
    public IEnumerable<StudioJob> RecentJobs => Jobs.Take(2);
    public IEnumerable<StudioJob> CompletedJobs => Jobs.Where(x => x.Status == "Concluído");
    public IEnumerable<StudioJob> ActivityJobs => Jobs.Where(x => Filter switch { "Baixando" => x.IsRunning, "Na fila" => x.Status == "Na fila", "Falhas" => x.Status == "Falhou", "Cancelados" => x.Status == "Cancelado", _ => x.Status != "Concluído" });
    public Choice[] Containers => (Kind == MediaKind.Video ? DownloadCommand.VideoContainers : DownloadCommand.AudioContainers).Select(x => new Choice(x, Label(x))).ToArray();
    public Choice[] Resolutions { get; } = new[] { "best", "4320", "2160", "1440", "1080", "720", "480", "360", "240", "144" }.Select(x => new Choice(x, x switch { "best" => "Melhor disponível", "4320" => "8K · 4320p", "2160" => "4K · 2160p", "1440" => "2K · 1440p", "1080" => "Full HD · 1080p", "720" => "HD · 720p", _ => x + "p" })).ToArray();
    public Choice[] AudioQualities { get; } = Enumerable.Range(0, 11).Select(x => new Choice(x.ToString(), x == 0 ? "Melhor qualidade · VBR 0" : $"VBR {x}")).Concat(new[] { "320K", "256K", "192K", "160K", "128K", "96K", "64K" }.Select(x => new Choice(x, x[..^1] + " kbps"))).ToArray();
    public Choice[] VideoCodecs => DownloadCommand.VideoCodecs.Select(x => new Choice(x, CodecLabel(x))).ToArray();
    public Choice[] AudioCodecs => DownloadCommand.AudioCodecs.Select(x => new Choice(x, CodecLabel(x))).ToArray();
    public Choice[] FrameRates { get; } = new[] { "any", "120", "60", "50", "30", "25", "24" }.Select(x => new Choice(x, x == "any" ? "Automático" : $"Até {x} fps")).ToArray();
    public DownloadOptions CurrentOptions => new() { Kind = Kind, Container = Container, Resolution = Resolution, AudioQuality = AudioQuality, VideoCodec = VideoCodec, AudioCodec = AudioCodec, Fps = Fps, Selector = Selector };
    private static bool ValidUrl(string value) => Uri.TryCreate(value, UriKind.Absolute, out var uri) && (uri.Scheme == "http" || uri.Scheme == "https") && !string.IsNullOrWhiteSpace(uri.Host);
    private static string Label(string value) => value switch { "auto" => "Original · sem remux", "best" => "Original · melhor áudio", "vorbis" => "OGG · Vorbis", "flac" => "FLAC · sem perdas", "alac" => "ALAC · sem perdas", "wav" => "WAV · sem perdas", _ => value.ToUpperInvariant() };
    private static string CodecLabel(string value) => value switch { "any" => "Automático · melhor disponível", "h264" => "H.264 / AVC", "hevc" => "H.265 / HEVC", "mpeg4" => "MPEG-4", "mpeg2" => "MPEG-2", "prores" => "ProRes", _ => value.ToUpperInvariant() };
    private void UpdateInput() { foreach (var p in new[] { nameof(CanAdd), nameof(CanProbe), nameof(LinkCountLabel), nameof(PlaceholderVisibility), nameof(ValidationError), nameof(DownloadButtonLabel) }) Changed(p); }
    private void UpdateJobs() { foreach (var p in new[] { nameof(ActiveCount), nameof(QueuedCount), nameof(DoneCount), nameof(ActivityJobs), nameof(CompletedJobs), nameof(RecentJobs), nameof(ActivityEmpty) }) Changed(p); }
    public void AddLinks()
    {
        if (!CanAdd) return;
        var urls = LinkList; var options = CurrentOptions; var path = Path.GetFullPath(Environment.ExpandEnvironmentVariables(Directory));
        foreach (string url in urls) Jobs.Insert(0, new(url, options, path));
        Links = ""; UpdateJobs(); StartNext();
    }
    public StudioJob Enqueue(string url, DownloadOptions options, string destination)
    { var job = new StudioJob(url, options, destination); Jobs.Insert(0, job); UpdateJobs(); StartNext(); return job; }
    public void Cancel(StudioJob job)
    {
        if (job.IsRunning) { job.Status = "Cancelando…"; job.Cancellation.Cancel(); }
        else if (job.Status == "Na fila") { job.Status = "Cancelado"; job.Cancellation.Cancel(); }
        UpdateJobs();
    }
    public void Retry(StudioJob job) { if (!job.IsRunning && job.Status is "Falhou" or "Cancelado") Enqueue(job.Url, job.Options, job.Directory); }
    public void Stop() { stopping = true; foreach (var job in Jobs.Where(x => x.IsRunning || x.Status == "Na fila").ToArray()) Cancel(job); }
    private void StartNext()
    {
        if (stopping) return;
        while (ActiveCount < 2 && Jobs.LastOrDefault(x => x.Status == "Na fila") is { } next)
        { next.IsRunning = true; next.Status = "Preparando"; UpdateJobs(); Run(next); }
    }
    private async void Run(StudioJob job)
    {
        try
        {
            var result = await service.RunAsync(job.Url, job.Options, job.Directory, update =>
            {
                Application.Current.Dispatcher.BeginInvoke(new Action(() =>
                {
                    if (!job.IsRunning || job.Cancellation.IsCancellationRequested) return;
                    if (update.Title is not null) job.Title = update.Title;
                    if (update.Progress is { } p) job.Progress = p;
                    if (update.Speed is not null) job.Speed = update.Speed;
                    if (update.Eta is not null) job.Eta = update.Eta;
                    if (update.Status is not null && update.Status is not ("Concluído" or "Falhou")) job.Status = update.Status;
                    if (update.Error is not null) job.Error = update.Error;
                }));
            }, job.Cancellation.Token);
            job.File = result.Path; job.Title = result.Title; job.Progress = 100; job.Error = ""; job.Status = "Concluído";
        }
        catch (OperationCanceledException) { job.Status = "Cancelado"; }
        catch (Exception ex) { job.Error = ex.Message; job.Status = "Falhou"; }
        finally { job.IsRunning = false; job.Speed = ""; job.Eta = ""; job.Refresh(); UpdateJobs(); StartNext(); }
    }
}
