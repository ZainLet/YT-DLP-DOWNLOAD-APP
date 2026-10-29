import Foundation

@main struct DownloadCoreChecks {
    @MainActor static func main() async throws {
        var options = DownloadOptions()
        var assertions = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); assertions += 1
        }
        check(DownloadCommand.selector(for: options) == "bv+ba/b", "Default selector")
        options.resolution = "2160"; options.videoCodec = "h264"; options.audioCodec = "aac"; options.fps = "60"
        let selector = DownloadCommand.selector(for: options)
        check(selector.contains("[height<=2160]"), "Resolution filter")
        check(selector.contains("[fps<=60]"), "FPS filter")
        check(selector.contains("avc|h264"), "AVC source matching")
        check(selector.contains("mp4a|aac"), "AAC source matching")
        options.selector = "137+140"
        check(DownloadCommand.selector(for: options) == "137+140", "Exact selector takes precedence")
        options.selector = ""; options.kind = .audio; options.container = "flac"; options.audioQuality = "320K"
        let args = DownloadCommand.arguments(url: "https://example.com/video", options: options)
        check(args.contains("flac") && args.contains("320K") && args.contains("-x"), "Lossless audio and bitrate")
        check(!args.contains("--remux-video"), "Audio does not use video remux")
        check(Array(args.suffix(2)) == ["--", "https://example.com/video"], "URLs are separate arguments")
        options.kind = .video; options.container = "auto"
        check(!DownloadCommand.arguments(url: "https://example.com", options: options).contains("--remux-video"), "Original container")
        check(DownloadCommand.arguments(url: "https://www.twitch.tv/videos/2903366879", options: options).contains("--hls-use-mpegts"), "Twitch HLS avoids MP4 timestamp fixup")
        check(!DownloadCommand.arguments(url: "https://evil-twitch.tv/videos/2903366879", options: options).contains("--hls-use-mpegts"), "Unrelated domains do not use Twitch HLS handling")
        let videoOnly = SourceFormat.parse(["format_id": "137", "ext": "mp4", "vcodec": "avc1", "acodec": "none", "height": 1080])!
        check(videoOnly.selector == "137+ba", "Video-only format gets audio")
        check(SourceFormat.parse(["format_id": "sb", "vcodec": "none", "acodec": "none"]) == nil, "Storyboards are excluded")
        print("PASS: \(assertions) command and format checks")

        if CommandLine.arguments.count > 2 {
            let base = CommandLine.arguments[1], destination = CommandLine.arguments[2]
            let manager = DownloadManager()
            options = DownloadOptions()
            manager.add(urls: (1...3).map { "\(base)/sample\($0).mp4" }, options: options, directory: destination)
            check(manager.activeCount == 2 && manager.queuedCount == 1, "Two processes and one queued")
            for _ in 0..<600 {
                if manager.activeCount == 0 && manager.queuedCount == 0 { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            check(manager.doneCount == 3, "Three real yt-dlp downloads: \(manager.jobs.map { "\($0.status): \($0.error)" })")
            check(manager.jobs.allSatisfy { !$0.file.isEmpty && FileManager.default.fileExists(atPath: $0.file) }, "Output paths exist")
            manager.loadFormats(url: "\(base)/sample1.mp4")
            for _ in 0..<300 {
                if !manager.loadingFormats { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            check(!manager.formats.isEmpty, "Actual source format probe: \(manager.formatError)")
            let audioManager = DownloadManager()
            for container in DownloadCommand.audioContainers {
                var audioOptions = DownloadOptions()
                audioOptions.kind = .audio; audioOptions.container = container
                audioManager.add(urls: ["\(base)/sample1.mp4"], options: audioOptions, directory: destination + "/audio/" + container)
            }
            for _ in 0..<1200 {
                if audioManager.activeCount == 0 && audioManager.queuedCount == 0 { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            check(audioManager.doneCount == DownloadCommand.audioContainers.count,
                  "All audio formats: \(audioManager.jobs.filter { $0.status != "Concluído" }.map { "\($0.options.container): \($0.error)" })")
            print("PASS: queue, concurrent processes, files and format probe (\(assertions) checks total)")
        }
    }
}
