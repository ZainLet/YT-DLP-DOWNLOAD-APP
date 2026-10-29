#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/.build/ModuleCache"
STAGING="$(mktemp -d "$ROOT/.build/package.XXXXXX")"
APP="$STAGING/YTDLP Studio.app"
CONTENTS="$APP/Contents"
ICONSET="$STAGING/AppIcon.iconset"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$ICONSET"

xcrun swiftc "$ROOT"/macOS/Sources/*.swift -o "$CONTENTS/MacOS/YTDLP Studio" \
  -framework SwiftUI -framework AppKit -parse-as-library -O \
  -target arm64-apple-macos14.0 -module-cache-path "$ROOT/.build/ModuleCache"

for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ROOT/assets/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$ROOT/assets/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
cp "$ROOT/macOS/Info.plist" "$CONTENTS/Info.plist"
if [ "${STUDIO_BUNDLE_TOOLS:-0}" = "1" ]; then
  test -x "$ROOT/.build/runtime/bin/yt-dlp"
  mkdir -p "$CONTENTS/Resources/Tools" "$CONTENTS/Resources/ThirdParty"
  cp "$ROOT/.build/runtime/bin/"* "$CONTENTS/Resources/Tools/"
  cp "$ROOT/.build/runtime/licenses/"* "$CONTENTS/Resources/ThirdParty/"
  cp "$ROOT/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/ThirdParty/"
  for TOOL in "$CONTENTS/Resources/Tools/"*; do codesign --force --sign - "$TOOL"; done
fi
plutil -lint "$CONTENTS/Info.plist"
codesign --force --sign - "$APP"

# Replace only after a successful build, keeping the previous bundle recoverable.
if [ -d "$ROOT/YTDLP Studio.app" ]; then
  PREVIOUS="$(mktemp -d "$ROOT/.build/previous.XXXXXX")"
  mv "$ROOT/YTDLP Studio.app" "$PREVIOUS/YTDLP Studio.bundle-backup"
fi
mv "$APP" "$ROOT/YTDLP Studio.app"
echo "Built: $ROOT/YTDLP Studio.app"
