# Third-party components / Componentes de terceiros

The standalone release bundles the following unmodified upstream components,
except for local ad-hoc signatures and the FFmpeg build configuration. The app
runs these as separate programs; their original licenses remain applicable.

| Component | Version | Source | License |
| --- | --- | --- | --- |
| yt-dlp standalone macOS | 2026.10.26 | [yt-dlp](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.26) | Unlicense; bundled dependencies have their own notices |
| FFmpeg / FFprobe | 8.0.1 | [FFmpeg source](https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz) | LGPL 2.1 or later; built without GPL/nonfree components |
| LAME | 3.100 | [LAME](https://sourceforge.net/projects/lame/files/lame/3.100/) | LGPL |
| libogg | 1.3.5 | [Xiph](https://downloads.xiph.org/releases/ogg/) | BSD-style |
| libvorbis | 1.3.7 | [Xiph](https://downloads.xiph.org/releases/vorbis/) | BSD-style |
| Opus | 1.5.2 | [Xiph](https://downloads.xiph.org/releases/opus/) | BSD-style and component notices |
| Deno | 2.9.8 | [Deno](https://github.com/denoland/deno/releases/tag/v2.9.8) | MIT and third-party notices |

Full notices are included under `YTDLP Studio.app/Contents/Resources/ThirdParty`.
The matching FFmpeg, LAME, Ogg, Vorbis, Opus and yt-dlp source archives are
published beside the installer as `YTDLP-Studio-1.2.0-ThirdPartySources.tar.gz`.
Build instructions and the exact configure flags are in `scripts/prepare_runtime.sh`.
Build checksums are pinned in `packaging/runtime-downloads.sha256`.

FFmpeg is built as standalone static command-line programs. To modify or replace
them, rebuild the supplied sources and replace `Contents/Resources/Tools/ffmpeg`
and `ffprobe`, then re-sign your local copy. No DRM or technical restriction is
applied to replacement of these components.

The yt-dlp standalone executable includes additional upstream components; consult
its bundled `THIRD_PARTY_LICENSES.txt`. Deno's upstream MIT license, Node
compatibility, V8 and TypeScript notices are included in the bundle. This software is based in part on the work of the Independent
JPEG Group through FFmpeg. No changes are made to the IJG-derived source files.

Em português: o instalador inclui os componentes acima, com suas licenças
originais. Os avisos completos ficam dentro do aplicativo; os arquivos-fonte
correspondentes e as instruções de compilação são disponibilizados na mesma
release. As ferramentas podem ser substituídas por versões recompiladas pelo
usuário. Os componentes de terceiros são fornecidos sem garantia, conforme
suas respectivas licenças.
