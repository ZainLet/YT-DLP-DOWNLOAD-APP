<div align="center">
  <img src="assets/AppIcon.png" width="104" alt="YTDLP Studio icon">
  <h1>YTDLP Studio</h1>
  <p>Videos and music, from a link to your Mac.</p>
  <p><a href="README.md">Português</a> · <strong>English</strong></p>
  <p><a href="https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP/releases/latest">Download for macOS</a> · <a href="#installation">Installation</a> · <a href="#building-from-source">Build from source</a></p>
</div>

A native macOS app built with SwiftUI and AppKit. It organizes batch [yt-dlp](https://github.com/yt-dlp/yt-dlp) downloads in a dark, translucent window with native blur and Liquid Glass controls.

## Installation

1. Open the [latest release](https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP/releases/latest).
2. Download `YTDLP-Studio-1.2.0-macOS-arm64.pkg` and follow the installer. It places the app in **Applications**.
3. Alternatively, download the `.dmg`, open it, and drag **YTDLP Studio** to **Applications**.
4. Launch **YTDLP Studio** from Applications or Spotlight.

The installer includes **yt-dlp, FFmpeg, FFprobe and Deno**. The distributed app does not require Python, Homebrew, or a terminal to use. The `.zip` contains the same app for manual installation.

**Signing status:** the app is locally ad-hoc signed; the installer has no Developer ID certificate, and this release is not Apple notarized. macOS may block the first launch. After checking the source and checksum, use **System Settings → Privacy & Security → Open Anyway**, if available. Do not disable Gatekeeper. Organizations requiring notarization may prevent this release from running.

### Requirements

| Item | Requirement |
| --- | --- |
| Mac | Apple Silicon: M1 or later |
| Operating system | macOS 14 or later |
| Liquid Glass | macOS 26 or later; standard controls on earlier versions |
| Connection | Internet access to the source media |
| Storage | App, bundled tools, and free space for downloaded files |

The distributed binary is **arm64**. An Intel build is not included in this release. The runtime was validated on macOS 27.2; the minimum build target is macOS 14.

## Features

- Add multiple links at once, one per line.
- Run up to **two simultaneous downloads**, with a queue for the rest.
- Navigate between native **Baixar** (Download), **Atividade** (Activity), and **Concluídos** (Completed) tabs.
- View titles, progress, speed, estimated time remaining, cancellation, and errors.
- Choose a destination folder and reveal completed files in Finder.
- Inspect the first link's actual source formats through **Formatos do link…** (Link formats).
- Filter resolution, frame rate, source codecs, audio quality, and exact format IDs.
- Use dark translucency and blur, respecting macOS **Reduce Transparency** and **Reduce Motion** settings.

### Formats and quality

| Category | Options |
| --- | --- |
| Video | Original, MP4, MKV, WebM, MOV, AVI, FLV, GIF |
| Audio | Original, MP3, M4A, AAC, Opus, OGG/Vorbis, FLAC, ALAC, WAV, AIFF, MKA |
| Maximum resolution | Best available, 8K, 4K, 1440p, 1080p, 720p, 480p, 360p, 240p, 144p |
| Maximum frame rate | Automatic, 120, 60, 50, 30, 25, 24 fps |
| Audio quality | VBR 0–10 and bitrates from 64 to 320 kbps |
| Source video codecs | Automatic, H.264/AVC, H.265/HEVC, AV1, VP9, VP8, MPEG-4, MPEG-2, Theora, ProRes |
| Source audio codecs | Automatic, AAC, Opus, Vorbis, MP3, FLAC, ALAC, PCM, AC3, EAC3, DTS |

Availability depends on the source website. A codec filter **selects an existing source stream**; it does not re-encode video. Changing a video container uses remuxing and may fail if that container cannot carry the selected codecs. Audio may be converted by FFmpeg; selecting FLAC or WAV cannot restore quality missing from the source. Bitrate settings do not apply to lossless formats in the same way as lossy formats.

For full control, use **Formatos do link…** or the advanced **yt-dlp selector**. Examples: `137+140`, `bv+ba/b`. A manual selector overrides the automatic resolution and codec filters. Storyboards without audio or video are excluded from the format table.

## Usage

1. In **Baixar**, paste one or more HTTP/HTTPS links, one per line.
2. Select **Vídeo** or **Áudio**, output format, quality, and destination.
3. Expand **Codecs e opções avançadas** to filter source streams when needed.
4. Click **Iniciar download** (Start download) or press **⌘ Return**.
5. Track progress in **Atividade**. Finished files appear in **Concluídos**.

| Shortcut | Action |
| --- | --- |
| ⌘ N | Go to a new download |
| ⌘ 1 / ⌘ 2 / ⌘ 3 | Download / Activity / Completed |
| ⌘ Return | Start the batch of links |

## Data and current limitations

- There is no hosted backend or app account. The bundled tools contact the source websites directly.
- The queue and history are **session-only**. Quitting the app resets the list; downloaded files remain on disk.
- Each link is handled as one item; automatic playlist expansion is disabled.
- This version's interface is in Portuguese. The documentation is available in [Portuguese](README.md) and English.
- DRM-protected media, required logins, regional restrictions, and changes to source websites may prevent downloads. The UI does not include login/cookie integration.
- Download only content you own or are authorized to save.

## Building from source

Requires Apple Silicon, Xcode 26 or later, and its command-line tools.

```bash
git clone https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP.git
cd YT-DLP-DOWNLOAD-APP
bash build_mac_app.sh
open "YTDLP Studio.app"
```

Development builds use tools available on `PATH`. For that mode, install `yt-dlp`, `ffmpeg`, and `deno`, for example with `brew install yt-dlp ffmpeg deno`.

### Building the standalone installer

Also requires `make`, `clang`, `pkg-config`, `curl`, `tar`, and the macOS packaging tools. Install `pkg-config` with `brew install pkgconf` if necessary.

```bash
bash scripts/prepare_runtime.sh
STUDIO_BUNDLE_TOOLS=1 bash build_mac_app.sh
bash scripts/package_release.sh
bash scripts/check_release.sh
```

Runtime versions are pinned, and downloads are checked against `packaging/runtime-downloads.sha256`. FFmpeg and its libraries are built from the supplied sources with static linking and without GPL/nonfree components. Artifacts appear in `dist/`: `.pkg`, `.dmg`, `.zip`, corresponding third-party sources, and `SHA256SUMS.txt`. The installer does not run scripts that download or install additional system components.

To verify a downloaded release, place the artifacts and `SHA256SUMS.txt` in the same folder and run `shasum -a 256 -c SHA256SUMS.txt`.

### Checks

```bash
mkdir -p .build/ModuleCache
xcrun swiftc macOS/Sources/DownloadCore.swift macOS/Tests/DownloadCoreChecks.swift \
  -parse-as-library -o .build/download-checks -module-cache-path .build/ModuleCache
.build/download-checks
```

The integration check accepts a local server URL containing `sample1.mp4`, `sample2.mp4`, and `sample3.mp4`, followed by a destination directory. It checks concurrency, queueing, output files, format inspection, and all 12 audio choices. Release checks also validate the local signature, checksums, and absence of Homebrew library dependencies.

## Project structure

```text
macOS/Sources/          App, interface, and download engine
macOS/Tests/            Command and queue checks
assets/                Application icon
packaging/             Installer configuration and content
scripts/               Portable runtime, packaging, and verification
build_mac_app.sh        .app build script
```

## Third-party components and credits

The app uses [yt-dlp](https://github.com/yt-dlp/yt-dlp), [FFmpeg](https://ffmpeg.org), [Deno](https://deno.com), LAME, and Xiph libraries. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for versions, licenses, corresponding sources, and component replacement instructions. The matching source archive is published alongside the installer in the same release.

The design references Apple's Human Interface Guidelines. This is an independent project, not affiliated with Apple or the yt-dlp project.
