#!/bin/bash
# Build redistributable, static audio tools from their corresponding sources.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$ROOT/.build/runtime"
SOURCES="$BASE/sources"
PREFIX="$BASE/prefix"
mkdir -p "$SOURCES" "$PREFIX" "$BASE/bin" "$BASE/licenses" "$BASE/logs"
export MACOSX_DEPLOYMENT_TARGET=14.0
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
JOBS="${STUDIO_BUILD_JOBS:-8}"

fetch() {
  if [ ! -s "$SOURCES/$2" ]; then
    curl -fLsS --retry 3 --connect-timeout 30 "$1" -o "$SOURCES/$2.download"
    mv "$SOURCES/$2.download" "$SOURCES/$2"
  fi
}
fetch https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz ffmpeg-8.0.1.tar.xz
fetch https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz lame-3.100.tar.gz
fetch https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.xz libogg-1.3.5.tar.xz
fetch https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.xz libvorbis-1.3.7.tar.xz
fetch https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz opus-1.5.2.tar.gz
fetch https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/yt-dlp_macos yt-dlp_macos
fetch https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/SHA2-256SUMS yt-dlp-SHA2-256SUMS
fetch https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/yt-dlp.tar.gz yt-dlp-2026.10.26.tar.gz
fetch https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.10.26/THIRD_PARTY_LICENSES.txt yt-dlp-THIRD_PARTY_LICENSES.txt
fetch https://github.com/denoland/deno/releases/download/v2.9.8/deno-aarch64-apple-darwin.zip deno-v2.9.8-aarch64-apple-darwin.zip
fetch https://raw.githubusercontent.com/denoland/deno/v2.9.8/LICENSE.md Deno-LICENSE.txt
fetch https://raw.githubusercontent.com/denoland/deno/v2.9.8/cli/tsc/dts/node/LICENSE Deno-Node-LICENSE.txt
fetch https://raw.githubusercontent.com/v8/v8/15.0.245.2/LICENSE Deno-V8-LICENSE.txt
fetch https://raw.githubusercontent.com/microsoft/TypeScript/v6.0.3/LICENSE.txt Deno-TypeScript-LICENSE.txt

# The lock covers every downloaded source and executable. Bootstrap it only once
# with --write-lock, then commit and verify it on every subsequent build.
if [ "${1:-}" = "--write-lock" ]; then
  (cd "$SOURCES" && shasum -a 256 *.tar.* yt-dlp_macos yt-dlp-SHA2-256SUMS yt-dlp-THIRD_PARTY_LICENSES.txt Deno-*.txt *.zip) > "$BASE/runtime-downloads.sha256"
else
  (cd "$SOURCES" && shasum -a 256 -c "$ROOT/packaging/runtime-downloads.sha256")
fi
EXPECTED="$(awk '$2 == "yt-dlp_macos" { print $1 }' "$SOURCES/yt-dlp-SHA2-256SUMS")"
ACTUAL="$(shasum -a 256 "$SOURCES/yt-dlp_macos" | awk '{print $1}')"
[ -n "$EXPECTED" ] && [ "$EXPECTED" = "$ACTUAL" ]

build_library() {
  local NAME="$1" ARCHIVE="$2"
  shift 2
  if [ ! -f "$BASE/$NAME.done" ]; then
    [ -d "$BASE/$NAME" ] || tar -xf "$SOURCES/$ARCHIVE" -C "$BASE"
    # libvorbis's old configure adds a PowerPC-only linker flag on modern macOS.
    # Override compiler optimization flags without modifying its source archive.
    (cd "$BASE/$NAME" && ./configure --prefix="$PREFIX" --disable-shared --enable-static "$@" && \
      make -j "$JOBS" CFLAGS="-O2 -mmacosx-version-min=14.0" && \
      make install CFLAGS="-O2 -mmacosx-version-min=14.0") > "$BASE/logs/$NAME.log" 2>&1
    touch "$BASE/$NAME.done"
  fi
}
build_library lame-3.100 lame-3.100.tar.gz --disable-frontend
build_library libogg-1.3.5 libogg-1.3.5.tar.xz
build_library libvorbis-1.3.7 libvorbis-1.3.7.tar.xz --with-ogg="$PREFIX"
build_library opus-1.5.2 opus-1.5.2.tar.gz --disable-extra-programs --disable-doc

if [ ! -f "$BASE/ffmpeg.done" ]; then
  [ -d "$BASE/ffmpeg-8.0.1" ] || tar -xf "$SOURCES/ffmpeg-8.0.1.tar.xz" -C "$BASE"
  (cd "$BASE/ffmpeg-8.0.1" && ./configure --prefix="$PREFIX" --cc=clang \
    --arch=arm64 --target-os=darwin --enable-static --disable-shared --disable-autodetect \
    --disable-doc --disable-debug --disable-ffplay --enable-libmp3lame --enable-libopus \
    --enable-libvorbis --enable-securetransport --enable-audiotoolbox --enable-videotoolbox \
    --pkg-config-flags=--static --extra-cflags="-I$PREFIX/include -mmacosx-version-min=14.0" \
    --extra-ldflags="-L$PREFIX/lib -mmacosx-version-min=14.0" && make -j "$JOBS" && make install) > "$BASE/logs/ffmpeg.log" 2>&1
  touch "$BASE/ffmpeg.done"
fi
cp "$PREFIX/bin/ffmpeg" "$PREFIX/bin/ffprobe" "$BASE/bin/"
cp "$SOURCES/yt-dlp_macos" "$BASE/bin/yt-dlp"
unzip -qo "$SOURCES/deno-v2.9.8-aarch64-apple-darwin.zip" -d "$BASE/bin"
chmod +x "$BASE/bin/"*

cp "$BASE/ffmpeg-8.0.1/COPYING.LGPLv2.1" "$BASE/licenses/FFmpeg-LGPL-2.1.txt"
cp "$BASE/ffmpeg-8.0.1/LICENSE.md" "$BASE/licenses/FFmpeg-LICENSE.txt"
cp "$BASE/lame-3.100/COPYING" "$BASE/licenses/LAME-LICENSE.txt"
cp "$BASE/libogg-1.3.5/COPYING" "$BASE/licenses/Ogg-LICENSE.txt"
cp "$BASE/libvorbis-1.3.7/COPYING" "$BASE/licenses/Vorbis-LICENSE.txt"
cp "$BASE/opus-1.5.2/COPYING" "$BASE/licenses/Opus-LICENSE.txt"
tar -xzf "$SOURCES/yt-dlp-2026.10.26.tar.gz" -C "$BASE"
cp "$BASE/yt-dlp/LICENSE" "$BASE/licenses/yt-dlp-LICENSE.txt"
cp "$SOURCES/yt-dlp-THIRD_PARTY_LICENSES.txt" "$BASE/licenses/yt-dlp-THIRD_PARTY_LICENSES.txt"
cp "$SOURCES/"Deno-*.txt "$BASE/licenses/"
"$BASE/bin/ffmpeg" -buildconf 2>&1 | sed "s|$ROOT|<BUILD_ROOT>|g" > "$BASE/licenses/FFmpeg-BUILD-CONFIG.txt"
for TOOL in yt-dlp ffmpeg ffprobe deno; do
  codesign --force --sign - "$BASE/bin/$TOOL"
done
echo "Portable runtime: $BASE/bin"
