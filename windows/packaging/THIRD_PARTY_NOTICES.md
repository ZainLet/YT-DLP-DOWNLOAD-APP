# Third party components / Componentes de terceiros

The Windows beta bundles the following independent programs and runtimes. Their
licenses, notices and exact download checksums are in `ThirdParty/` in the
installed application. Matching source archives and reproducible build scripts
are provided in the release's `ThirdPartySources.zip`.

| Component | Version | License and source |
| --- | --- | --- |
| yt-dlp Windows standalone | 2026.10.26 | Unlicense and bundled notices; [release and sources](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.26) |
| Deno JavaScript runtime | 2.9.8 | MIT and upstream V8/Node/TypeScript notices; [release and sources](https://github.com/denoland/deno/releases/tag/v2.9.8) |
| FFmpeg and FFprobe | 8.0.1 | LGPL 2.1 or later, statically built without GPL, version 3, or nonfree options; matching source archives and build configuration supplied |
| LAME | 3.100 | LGPL; matching source archive supplied |
| .NET 10 | runtime included | MIT and third-party notices; complete licenses included in `ThirdParty/dotnet/` |

The corresponding matching source archives, build script, dependency hash lock,
and FFmpeg build configuration are supplied alongside the installer. The FFmpeg
distribution is not covered by GPL and uses only Windows system DLLs. The full
compiler configuration and notices are inside the installation and in the
source archive. Third party tools run as separate processes; each retains its
own upstream terms. The YTDLP Studio application is an independent project and
is not affiliated with Apple, Microsoft, FFmpeg, Deno, or yt-dlp.

## Português

A beta para Windows inclui os programas e runtimes independentes da tabela.
Licenças, avisos e checksums exatos ficam na pasta `ThirdParty/` do aplicativo.
Os arquivos fonte correspondentes e os scripts de compilação são publicados
com o instalador em `ThirdPartySources.zip`. O FFmpeg está compilado sem opções
GPL, não livres ou da versão 3; sua distribuição usa apenas bibliotecas de
sistema do Windows. Os componentes mantêm suas licenças originais. O YTDLP
Studio é um projeto independente, sem afiliação com a Apple, Microsoft, FFmpeg,
Deno ou yt-dlp.
