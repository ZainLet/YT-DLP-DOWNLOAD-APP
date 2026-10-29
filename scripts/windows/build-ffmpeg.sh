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
    if item['name'].startswith(('ffmpeg-', 'lame-')):
        p=pathlib.Path(sys.argv[2])/item['name']
        if hashlib.file_digest(p.open('rb'), 'sha256').hexdigest()!=item['sha256']:
            raise SystemExit('Source hash mismatch: '+str(p))
PY
# Always rebuild from pristine inputs; never trust a stale .done marker.
rm -rf "$BASE/ffmpeg-work/ffmpeg-8.0.1" "$BASE/ffmpeg-work/lame-3.100" "$PREFIX"
mkdir -p "$PREFIX"
tar -xf "$BASE/downloads/ffmpeg-8.0.1.tar.xz" -C "$BASE/ffmpeg-work"
tar -xf "$BASE/downloads/lame-3.100.tar.gz" -C "$BASE/ffmpeg-work"
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
    cd "$BASE/ffmpeg-work/ffmpeg-8.0.1"
    ./configure --prefix="$PREFIX" --target-os=mingw32 --arch=x86_64 --cc=gcc \
        --enable-static --disable-shared --disable-autodetect --disable-gpl --disable-nonfree \
        --disable-version3 --disable-doc --disable-debug --disable-ffplay --disable-x86asm \
        --disable-pthreads --enable-w32threads --enable-libmp3lame --enable-schannel \
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
"$BASE/publish/tools/ffmpeg.exe" -buildconf > "$NOTICES/FFmpeg-BUILD-CONFIG.txt" 2>&1
"$BASE/publish/tools/ffmpeg.exe" -L > "$NOTICES/FFmpeg-LICENSE-OUTPUT.txt" 2>&1
grep -q 'GNU Lesser General Public License' "$NOTICES/FFmpeg-LICENSE-OUTPUT.txt"
if grep -q -- '--enable-gpl\|--enable-nonfree\|--enable-version3' "$NOTICES/FFmpeg-BUILD-CONFIG.txt"; then exit 1; fi
cp "$BASE/ffmpeg-work/ffmpeg-8.0.1/ffbuild/config.log" "$BASE/evidence/ffmpeg-config.log"
cp "$BASE/ffmpeg-work/lame-3.100/config.log" "$BASE/evidence/lame-config.log"
