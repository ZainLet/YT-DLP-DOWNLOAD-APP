# Building the Windows runtime

The Windows release is built on an `windows-2025` x64 worker with the .NET 10
SDK, Python 3, and MSYS2 MINGW64. `dependencies.lock.json` fixes the SHA-256 of
every downloaded executable, license, build tool and source archive.

1. Build the WPF app self-contained for `win-x64`.
2. Run `scripts/windows/prepare-runtime.ps1` to download and verify the locked
   yt-dlp, Deno, licenses and source archives.
3. Install `mingw-w64-x86_64-toolchain`, `make`, `pkgconf`, `xz`, and
   `diffutils` into an MSYS2 MINGW64 environment. Run
   `scripts/windows/build-ffmpeg.sh` from that shell.
   It builds LAME, Ogg, Vorbis, Opus and FFmpeg from the supplied versioned
   sources, with static linking and without GPL, version 3 or nonfree
   components. It also checks the
   resulting PE imports against Windows system libraries and records the
   configure command and build logs.
4. `scripts/windows/package.ps1` verifies the standalone .NET runtime, bundled
   tools, FFmpeg license and compiler options, copies the corresponding source
   archives into the release, builds the per-user Inno Setup installer, creates
   a portable ZIP, and writes SHA-256 checksums.
5. `scripts/windows/test-distribution.ps1` checks both archives, starts each
   packaged application on the Windows desktop runner, and installs and
   uninstalls the per-user installer before checking that it left no app files
   or registry entry.

The FFmpeg sources and the exact build scripts/configuration ship in
`YTDLP-Studio-<version>-ThirdPartySources.zip`. They are the same version and
configuration used for the included binaries.
