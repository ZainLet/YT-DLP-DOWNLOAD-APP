#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/YTDLP Studio.app}"
TOOLS="$APP/Contents/Resources/Tools"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
for TOOL in yt-dlp ffmpeg ffprobe deno; do
  test -x "$TOOLS/$TOOL"
  if otool -L "$TOOLS/$TOOL" | awk '/^\t/ {print $1}' | /usr/bin/grep -E '/opt/homebrew|/usr/local|/Users/' ; then
    echo "Non-portable linkage in $TOOL" >&2
    exit 1
  fi
done
"$TOOLS/yt-dlp" --version
"$TOOLS/ffmpeg" -version | sed -n '1p'
"$TOOLS/ffprobe" -version | sed -n '1p'
"$TOOLS/deno" --version
(cd "$ROOT/dist" && shasum -a 256 -c SHA256SUMS.txt)
echo "Release checks passed."
