# YTDLP Studio for Windows · Beta

This is the first Windows beta of YTDLP Studio. It is a native Windows desktop app that brings the macOS app's dark, translucent style, tabs, batch input, queue, format selection, and download history to Windows.

## Install

1. Download the newest `YTDLP-Studio-1.3.0-beta.*-win-x64-Setup.exe` for a per-user installation, or the matching `YTDLP-Studio-1.3.0-beta.*-win-x64-Portable.zip` to run without installing.
2. The installer includes the app, yt-dlp, FFmpeg, FFprobe, and Deno. No Python, package manager, or separate runtime setup is required.
3. Check `SHA256SUMS` before installing if you want to verify the download.

This beta is unsigned. Windows SmartScreen may show a warning; check that the file came from this GitHub release before choosing to run it.

## Beta scope

- Windows 10 version 22H2 (build 19045) and Windows 11, x64.
- Video and audio downloads, source format selection, codecs, and batch queues.
- The workflow builds and packages the app on Windows and checks its queue, local media conversions, portable archive, per-user install, and uninstall.
- Test on a Windows desktop before relying on the beta. This release has not been validated on every Windows version, website, or GPU/display configuration.

Only download media you own or have permission to save. The app does not provide a service for bypassing DRM, logins, or other access controls.

The app uses yt-dlp, FFmpeg, Deno, LAME, and .NET. Notices and the corresponding source archive are included in this release.
