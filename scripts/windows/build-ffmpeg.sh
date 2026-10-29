#!/usr/bin/env bash
# Run in MSYS2 MINGW64; no source modifications or GPL/nonfree dependencies.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASE="$ROOT/.build/windows"
PREFIX="$BASE/ffmpeg-prefix"
export PATH="/mingw64/bin:/usr/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export LC_ALL=C
mkdir -p "$BASE/ffmpeg-work" "$PREFIX" "$BASE/evidence" "$BASE/publish/tools" "$BASE/publish/ThirdParty"
# Reverify at the point of use, including on local repeat builds.
python - "$ROOT/windows/packaging/dependencies.lock.json" "$BASE/downloads" <<'PY'
import hashlib,json,pathlib,sys
for item in json.load(open(sys.argv[1]))['downloads']:
    if item['name'].startswith(('ffmpeg-', 'lame-', 'libogg-', 'libvorbis-', 'opus-')):
        p=pathlib.Path(sys.argv[2])/item['name']
        if hashlib.file_digest(p.open('rb'), 'sha256').hexdigest()!=item['sha256']:
            raise SystemExit('Source hash mismatch: '+str(p))
PY
# Always rebuild from pristine inputs; never trust a stale .done marker.
rm -rf "$BASE/ffmpeg-work/ffmpeg-8.0.1" "$BASE/ffmpeg-work/lame-3.100" \
    "$BASE/ffmpeg-work/libogg-1.3.6" "$BASE/ffmpeg-work/libvorbis-1.3.7" \
    "$BASE/ffmpeg-work/opus-1.6.1" "$PREFIX"
mkdir -p "$PREFIX"
tar -xf "$BASE/downloads/ffmpeg-8.0.1.tar.xz" -C "$BASE/ffmpeg-work"
tar -xf "$BASE/downloads/lame-3.100.tar.gz" -C "$BASE/ffmpeg-work"
tar -xf "$BASE/downloads/libogg-1.3.6.tar.gz" -C "$BASE/ffmpeg-work"
tar -xf "$BASE/downloads/libvorbis-1.3.7.tar.gz" -C "$BASE/ffmpeg-work"
tar -xf "$BASE/downloads/opus-1.6.1.tar.gz" -C "$BASE/ffmpeg-work"
pacman -Q > "$BASE/evidence/msys2-packages.txt"
gcc --version > "$BASE/evidence/gcc-version.txt"
JOBS="${STUDIO_BUILD_JOBS:-$(nproc)}"
(
    cd "$BASE/ffmpeg-work/lame-3.100"
    ./configure --prefix="$PREFIX" --host=x86_64-w64-mingw32 --enable-static --disable-shared --disable-frontend --disable-decoder --disable-nasm
    make -j "$JOBS"
    make install
) 2>&1 | tee "$BASE/evidence/lame-build.log"
(
    cd "$BASE/ffmpeg-work/libogg-1.3.6"
    ./configure --prefix="$PREFIX" --host=x86_64-w64-mingw32 --enable-static --disable-shared
    make -j "$JOBS"
    make install
) 2>&1 | tee "$BASE/evidence/libogg-build.log"
(
    cd "$BASE/ffmpeg-work/opus-1.6.1"
    ./configure --prefix="$PREFIX" --host=x86_64-w64-mingw32 --enable-static --disable-shared --disable-doc --disable-extra-programs --disable-asm
    make -j "$JOBS"
    make install
) 2>&1 | tee "$BASE/evidence/opus-build.log"
(
    cd "$BASE/ffmpeg-work/libvorbis-1.3.7"
    CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
        ./configure --prefix="$PREFIX" --host=x86_64-w64-mingw32 --enable-static --disable-shared --disable-oggtest --disable-examples
    make -j "$JOBS"
    make install
) 2>&1 | tee "$BASE/evidence/libvorbis-build.log"
(
    cd "$BASE/ffmpeg-work/ffmpeg-8.0.1"
    ./configure --prefix="$PREFIX" --target-os=mingw32 --arch=x86_64 --cc=gcc \
        --enable-static --disable-shared --disable-autodetect --disable-gpl --disable-nonfree \
        --disable-version3 --disable-doc --disable-debug --disable-ffplay --disable-x86asm \
        --disable-pthreads --enable-w32threads --enable-libmp3lame --enable-libopus --enable-libvorbis --enable-schannel \
        --pkg-config-flags=--static --extra-cflags="-I$PREFIX/include" \
        --extra-ldflags="-L$PREFIX/lib -static -static-libgcc"
    make -j "$JOBS"
    make install
) 2>&1 | tee "$BASE/evidence/ffmpeg-build.log"
for tool in ffmpeg ffprobe; do
    cp "$PREFIX/bin/$tool.exe" "$BASE/publish/tools/"
    objdump -p "$PREFIX/bin/$tool.exe" > "$BASE/evidence/$tool-pe.txt"
    # A static distribution must depend only on Windows system libraries.
    python - "$BASE/evidence/$tool-pe.txt" <<'PY'
import re,sys
allowed={'advapi32.dll','avicap32.dll','avrt.dll','bcrypt.dll','crypt32.dll','d3d11.dll','d3d12.dll','dxgi.dll','dwmapi.dll','gdi32.dll','imm32.dll','kernel32.dll','ksuser.dll','mf.dll','mfplat.dll','mfreadwrite.dll','mfuuid.dll','msvcrt.dll','ncrypt.dll','ntdll.dll','ole32.dll','oleaut32.dll','psapi.dll','secur32.dll','setupapi.dll','shell32.dll','shlwapi.dll','strmiids.dll','user32.dll','uuid.dll','vfw32.dll','winmm.dll','ws2_32.dll'}
names=re.findall(r'DLL Name:\s*(\S+)',open(sys.argv[1]).read())
bad=[n for n in names if n.lower() not in allowed and not n.lower().startswith(('api-ms-win-','ext-ms-win-'))]
if not names or bad: raise SystemExit('Unexpected runtime DLL dependency: '+repr(bad))
PY
done
NOTICES="$BASE/publish/ThirdParty"
cp "$BASE/ffmpeg-work/ffmpeg-8.0.1/COPYING.LGPLv2.1" "$NOTICES/FFmpeg-LGPL-2.1.txt"
cp "$BASE/ffmpeg-work/ffmpeg-8.0.1/LICENSE.md" "$NOTICES/FFmpeg-LICENSE.txt"
cp "$BASE/ffmpeg-work/lame-3.100/COPYING" "$NOTICES/LAME-LICENSE.txt"
cp "$BASE/ffmpeg-work/libogg-1.3.6/COPYING" "$NOTICES/Ogg-LICENSE.txt"
cp "$BASE/ffmpeg-work/libvorbis-1.3.7/COPYING" "$NOTICES/Vorbis-LICENSE.txt"
cp "$BASE/ffmpeg-work/opus-1.6.1/COPYING" "$NOTICES/Opus-LICENSE.txt"
"$BASE/publish/tools/ffmpeg.exe" -buildconf > "$NOTICES/FFmpeg-BUILD-CONFIG.txt" 2>&1 || {
    cat "$NOTICES/FFmpeg-BUILD-CONFIG.txt" >&2
    echo 'Could not inspect the FFmpeg build configuration.' >&2
    exit 1
}
"$BASE/publish/tools/ffmpeg.exe" -L > "$NOTICES/FFmpeg-LICENSE-OUTPUT.txt" 2>&1 || {
    cat "$NOTICES/FFmpeg-LICENSE-OUTPUT.txt" >&2
    echo 'Could not inspect the FFmpeg license output.' >&2
    exit 1
}
# FFmpeg wraps this phrase across lines, so normalize whitespace before checking.
python - "$NOTICES/FFmpeg-LICENSE-OUTPUT.txt" "$NOTICES/FFmpeg-BUILD-CONFIG.txt" <<'PY'
import pathlib, re, sys
license_text = re.sub(r'\s+', ' ', pathlib.Path(sys.argv[1]).read_text()).lower()
build_config = pathlib.Path(sys.argv[2]).read_text().lower()
if 'gnu lesser general public license' not in license_text:
    raise SystemExit('FFmpeg did not identify itself as an LGPL build; see FFmpeg-LICENSE-OUTPUT.txt')
enabled_forbidden = re.search(r'(?<!\S)--enable-(?:gpl|nonfree|version3)(?=\s|$)', build_config)
if enabled_forbidden:
    raise SystemExit('FFmpeg build enables a GPL, nonfree, or LGPLv3 option: ' + enabled_forbidden.group(0))
PY
cp "$BASE/ffmpeg-work/ffmpeg-8.0.1/ffbuild/config.log" "$BASE/evidence/ffmpeg-config.log"
cp "$BASE/ffmpeg-work/lame-3.100/config.log" "$BASE/evidence/lame-config.log"
