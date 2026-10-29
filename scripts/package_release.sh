#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/macOS/Info.plist")"
NAME="YTDLP-Studio-$VERSION-macOS-arm64"
OUT="$ROOT/dist"
STAGE="$(mktemp -d "$ROOT/.build/release.XXXXXX")"
APP="$ROOT/YTDLP Studio.app"
mkdir -p "$OUT" "$STAGE/payload/Applications" "$STAGE/dmg"
test -x "$APP/Contents/Resources/Tools/yt-dlp"
test -x "$APP/Contents/Resources/Tools/ffmpeg"
test -x "$APP/Contents/Resources/Tools/deno"
codesign --verify --deep --strict "$APP"
ditto "$APP" "$STAGE/payload/Applications/YTDLP Studio.app"
pkgbuild --root "$STAGE/payload" --component-plist "$ROOT/packaging/Component.plist" \
  --identifier local.ytdlp.studio --version "$VERSION" --install-location / \
  --ownership recommended "$STAGE/YTDLP-Studio-component.pkg"
productbuild --distribution "$ROOT/packaging/Distribution.xml" \
  --resources "$ROOT/packaging/resources" --package-path "$STAGE" "$OUT/$NAME.pkg"

ditto "$APP" "$STAGE/dmg/YTDLP Studio.app"
ln -s /Applications "$STAGE/dmg/Applications"
cp "$ROOT/README.md" "$STAGE/dmg/Leia-me.md"
cp "$ROOT/README.en.md" "$STAGE/dmg/Read-me.md"
hdiutil create -volname "YTDLP Studio" -srcfolder "$STAGE/dmg" -ov -format UDZO "$OUT/$NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME.zip"

mkdir -p "$STAGE/corresponding-sources"
cp "$ROOT/.build/runtime/sources/"*.tar.* "$STAGE/corresponding-sources/"
cp "$ROOT/scripts/prepare_runtime.sh" "$STAGE/corresponding-sources/"
cp "$ROOT/packaging/runtime-downloads.sha256" "$STAGE/corresponding-sources/"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/corresponding-sources/"
cp "$ROOT/packaging/SOURCE_BUILD.md" "$STAGE/corresponding-sources/BUILDING.md"
ditto "$ROOT/.build/runtime/licenses" "$STAGE/corresponding-sources/licenses"
tar -czf "$OUT/YTDLP-Studio-$VERSION-ThirdPartySources.tar.gz" -C "$STAGE" corresponding-sources
(cd "$OUT" && shasum -a 256 "$NAME.pkg" "$NAME.dmg" "$NAME.zip" "YTDLP-Studio-$VERSION-ThirdPartySources.tar.gz") > "$OUT/SHA256SUMS.txt"
echo "Release artifacts: $OUT"
