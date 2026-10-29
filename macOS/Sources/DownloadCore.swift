import Foundation
import Combine

enum MediaKind: String, CaseIterable { case video = "Vídeo", audio = "Áudio" }

enum ToolRuntime {
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Tools").path ?? ""
        let tools = env["STUDIO_TOOL_DIR"] ?? bundled
        let fallback = env["STUDIO_TOOLS_ONLY"] == "1" ? "/usr/bin:/bin:/usr/sbin:/sbin" : "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = "\(tools):\(fallback)"
        env["DENO_NO_UPDATE_CHECK"] = "1"
        return env
    }
}

struct DownloadOptions {
    var kind: MediaKind = .video
    var container = "mp4"
    var resolution = "best"
    var videoCodec = "any"
    var audioCodec = "any"
    var audioQuality = "0"
    var fps = "any"
    var selector = ""
}

enum DownloadCommand {
    private static let hasLibvorbis: Bool = {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ffmpeg", "-hide_banner", "-encoders"]
        process.environment = ToolRuntime.environment; process.standardOutput = pipe; process.standardError = pipe
        guard (try? process.run()) != nil else { return false }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text.contains("libvorbis")
    }()
    static let videoContainers = ["auto", "mp4", "mkv", "webm", "mov", "avi", "flv", "gif"]
    static let audioContainers = ["best", "mp3", "m4a", "aac", "opus", "vorbis", "flac", "alac", "wav", "aiff", "mka", "ogg"]
    static let videoCodecs = ["any", "h264", "hevc", "av1", "vp9", "vp8", "mpeg4", "mpeg2", "theora", "prores"]
    static let audioCodecs = ["any", "aac", "opus", "vorbis", "mp3", "flac", "alac", "pcm", "ac3", "eac3", "dts"]

    static func isTwitchURL(_ url: String) -> Bool {
        let host = URLComponents(string: url)?.host?.lowercased() ?? ""
        return host == "twitch.tv" || host.hasSuffix(".twitch.tv")
    }

    static func codecFilter(_ codec: String, video: Bool) -> String {
        guard codec != "any" else { return "" }
        let aliases = ["h264": "avc|h264", "hevc": "hev|hvc|hevc|h265", "av1": "av01|av1", "vp9": "vp09|vp9", "vp8": "vp08|vp8", "aac": "mp4a|aac", "mpeg2": "mpeg2", "pcm": "pcm"]
        return "[\(video ? "vcodec" : "acodec")~='^(\(aliases[codec] ?? codec))']"
    }

    static func selector(for options: DownloadOptions) -> String {
        if !options.selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return options.selector }
        let audio = codecFilter(options.audioCodec, video: false)
        if options.kind == .audio { return "ba\(audio)/b\(audio)" }
        var video = codecFilter(options.videoCodec, video: true)
        if options.resolution != "best" { video += "[height<=\(options.resolution)]" }
        if options.fps != "any" { video += "[fps<=\(options.fps)]" }
        return "bv\(video)+ba\(audio)/b\(video)\(audio)"
    }

    static func arguments(url: String, options: DownloadOptions) -> [String] {
        var args = ["--ignore-config", "--no-playlist", "--newline", "--no-color", "--no-overwrites",
                    "--progress-template", "download:STUDIO_PROGRESS:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
                    "--print", "before_dl:STUDIO_TITLE:%(title)s", "--print", "after_move:STUDIO_FILE:%(filepath)s",
                    "--no-simulate", "-o", "%(title).180s [%(id)s].%(ext)s", "-f", selector(for: options)]
        // Twitch VODs use HLS segments. Keep the downloaded stream in MPEG-TS so yt-dlp
        // does not apply its known MPEG-TS-in-MP4 AAC timestamp fixup, which can truncate
        // long VODs. The user's selected container is still applied below via remux.
        let isTwitch = isTwitchURL(url)
        if isTwitch {
            args.append("--hls-use-mpegts")
        }
        if options.kind == .audio {
            let extras = ["aiff", "mka", "ogg"]
            args += ["-x", "--audio-format", extras.contains(options.container) ? "best" : options.container,
                     "--audio-quality", options.audioQuality]
            if options.container == "vorbis" && !hasLibvorbis {
                args += ["--postprocessor-args", "ExtractAudio+ffmpeg_o:-c:a vorbis -strict experimental -ac 2"]
            }
            if extras.contains(options.container) { args += ["--recode-video", options.container] }
        } else if options.container != "auto" {
            // Remux changes the container, not the encoded video. Unsupported pairs fail visibly.
            args += ["--remux-video", options.container]
        } else if isTwitch {
            // HLS is downloaded as MPEG-TS to avoid long-VOD timestamp truncation.
            // Keep the default user-facing video format useful by remuxing to MP4 without re-encoding.
            args += ["--remux-video", "mp4"]
        }
        return args + ["--", url]
    }
}

struct SourceFormat: Identifiable {
    let id: String
    let ext: String
    let resolution: String
    let videoCodec: String
    let audioCodec: String
    let detail: String
    let filesize: Double?
    var hasVideo: Bool { videoCodec != "none" && !videoCodec.isEmpty }
    var hasAudio: Bool { audioCodec != "none" && !audioCodec.isEmpty }
    var selector: String { hasVideo && !hasAudio ? "\(id)+ba" : id }

    static func parse(_ value: [String: Any]) -> SourceFormat? {
        guard let id = value["format_id"] as? String else { return nil }
        let video = value["vcodec"] as? String ?? "unknown"
        let audio = value["acodec"] as? String ?? "unknown"
        guard video != "none" || audio != "none" else { return nil }
        return SourceFormat(id: id, ext: value["ext"] as? String ?? "—",
                            resolution: value["resolution"] as? String ?? ((value["height"] as? Int).map { "\($0)p" } ?? (video == "none" ? "Somente áudio" : "Não informada")),
                            videoCodec: video, audioCodec: audio,
                            detail: value["format_note"] as? String ?? "",
                            filesize: value["filesize"] as? Double ?? value["filesize_approx"] as? Double)
    }
}

struct DownloadJob: Identifiable {
    let id = UUID()
    let url: String
    let options: DownloadOptions
    let directory: String
    var title = ""
    var status = "Na fila"
    var progress = 0.0
    var speed = ""
    var eta = ""
    var error = ""
    var file = ""
    var process: Process?
    var isActive: Bool { ["Preparando", "Baixando", "Finalizando", "Cancelando…"].contains(status) }
}

@MainActor final class DownloadManager: ObservableObject {
    @Published var jobs: [DownloadJob] = []
    @Published var formats: [SourceFormat] = []
    @Published var formatTitle = ""
    @Published var formatError = ""
    @Published var loadingFormats = false
    private var probe: Process?
    var activeCount: Int { jobs.filter(\.isActive).count }
    var queuedCount: Int { jobs.filter { $0.status == "Na fila" }.count }
    var doneCount: Int { jobs.filter { $0.status == "Concluído" }.count }

    static var environment: [String: String] {
        ToolRuntime.environment
    }

    func add(urls: [String], options: DownloadOptions, directory: String) {
        let path = NSString(string: directory).expandingTildeInPath
        for url in urls { jobs.insert(DownloadJob(url: url, options: options, directory: path), at: 0) }
        startNext()
    }

    func cancel(_ job: DownloadJob) {
        guard let i = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        if jobs[i].status == "Na fila" { jobs[i].status = "Cancelado" }
        else if jobs[i].isActive { jobs[i].status = "Cancelando…"; jobs[i].process?.terminate() }
    }

    private func startNext() {
        while activeCount < 2, let i = jobs.lastIndex(where: { $0.status == "Na fila" }) {
            jobs[i].status = "Preparando"
            launch(jobs[i])
        }
    }

    private func launch(_ job: DownloadJob) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["yt-dlp"] + DownloadCommand.arguments(url: job.url, options: job.options)
        process.environment = Self.environment
        process.currentDirectoryURL = URL(fileURLWithPath: job.directory)
        process.standardOutput = pipe; process.standardError = pipe
        do {
            try FileManager.default.createDirectory(atPath: job.directory, withIntermediateDirectories: true)
            if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i].process = process }
            try process.run()
            DispatchQueue.global(qos: .utility).async {
                var buffer = Data()
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                    while let end = buffer.firstIndex(of: 10) {
                        let line = String(decoding: buffer[..<end], as: UTF8.self)
                        buffer.removeSubrange(...end)
                        DispatchQueue.main.async { self.consume(line, id: job.id) }
                    }
                }
                if !buffer.isEmpty {
                    let line = String(decoding: buffer, as: UTF8.self)
                    DispatchQueue.main.async { self.consume(line, id: job.id) }
                }
                process.waitUntilExit()
                DispatchQueue.main.async { self.finish(job.id, code: process.terminationStatus) }
            }
        } catch {
            consume("ERROR: \(error.localizedDescription)", id: job.id)
            finish(job.id, code: 1)
        }
    }

    private func consume(_ line: String, id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        if line.hasPrefix("STUDIO_TITLE:") { jobs[i].title = String(line.dropFirst(13)) }
        if line.hasPrefix("STUDIO_FILE:") { jobs[i].file = String(line.dropFirst(12)) }
        if line.hasPrefix("STUDIO_PROGRESS:"), jobs[i].status != "Cancelando…" {
            let fields = line.dropFirst(16).split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            if let first = fields.first, let percent = Double(first.replacingOccurrences(of: "%", with: "")) {
                jobs[i].progress = percent; jobs[i].status = percent >= 100 ? "Finalizando" : "Baixando"
            }
            if fields.count > 1 { jobs[i].speed = fields[1] == "N/A" ? "" : fields[1] }
            if fields.count > 2 { jobs[i].eta = fields[2] == "N/A" ? "" : fields[2] }
        }
        if line.contains("ERROR:") { jobs[i].error = line.replacingOccurrences(of: "ERROR: ", with: "") }
    }

    private func finish(_ id: UUID, code: Int32) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        let cancelled = jobs[i].status == "Cancelando…"
        jobs[i].status = cancelled ? "Cancelado" : code == 0 ? "Concluído" : "Falhou"
        if code == 0 { jobs[i].progress = 100 }
        if code != 0 && !cancelled && jobs[i].error.isEmpty { jobs[i].error = "Verifique o link e a disponibilidade do formato ou codec selecionado." }
        jobs[i].process = nil
        startNext()
    }

    func loadFormats(url: String) {
        guard !loadingFormats else { return }
        formats = []; formatError = ""; formatTitle = ""; loadingFormats = true
        let process = Process(), pipe = Pipe(), errors = Pipe()
        probe = process
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["yt-dlp", "--ignore-config", "--no-playlist", "--dump-single-json", "--skip-download", "--no-warnings", "--socket-timeout", "15", "--", url]
        process.environment = Self.environment
        process.standardOutput = pipe; process.standardError = errors
        do {
            try process.run()
            // Drain stderr alongside stdout so neither pipe can fill and deadlock the probe.
            errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errors.fileHandleForReading.readabilityHandler = nil
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let results = (json?["formats"] as? [[String: Any]] ?? []).compactMap(SourceFormat.parse)
                let title = json?["title"] as? String ?? "Formatos disponíveis"
                DispatchQueue.main.async {
                    self.loadingFormats = false; self.probe = nil
                    self.formats = results.reversed(); self.formatTitle = title
                    if results.isEmpty { self.formatError = "Não foi possível consultar os formatos. Verifique o link ou tente novamente." }
                }
            }
        } catch { loadingFormats = false; formatError = error.localizedDescription; probe = nil }
    }

    func cancelProbe() { probe?.terminate() }
}
