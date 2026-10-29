## Português

Primeira release pública do **YTDLP Studio**, um gerenciador nativo de downloads para macOS.

- Fundo escuro translúcido, desfoque e Liquid Glass nativo.
- Links em lote, fila e dois downloads simultâneos.
- Formatos de vídeo/áudio, resolução até 8K, FPS, bitrate e filtros de codec.
- Consulta dos formatos reais de cada link e seletor avançado.
- **yt-dlp, FFmpeg, FFprobe e Deno incluídos**: dispensa Homebrew e Python no uso normal.

**Instalação:** baixe o `.pkg` ou arraste o app do `.dmg` para Aplicativos. Requer **Apple Silicon (M1+) e macOS 14+**. Liquid Glass requer macOS 26+. O runtime foi validado no macOS 27.2.

**Assinatura:** app ad hoc, instalador sem Developer ID e sem notarização Apple. O macOS pode exigir “Abrir Mesmo Assim” em Privacidade e Segurança. Não desative o Gatekeeper.

Fila e histórico são mantidos apenas na sessão. Formatos/codecs dependem do site; o vídeo é remuxado sem recodificação. Leia o [README em português](https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP/blob/main/README.md).

## English

First public release of **YTDLP Studio**, a native macOS download manager.

- Dark translucent window, native blur, and Liquid Glass controls.
- Batch links, queueing, and two concurrent downloads.
- Video/audio formats, up to 8K resolution, frame rate, bitrate, and source codec filters.
- Source-format inspection and an advanced yt-dlp selector.
- **yt-dlp, FFmpeg, FFprobe and Deno bundled**: no Homebrew or Python required for normal use.

**Install:** use the `.pkg`, or drag the app from the `.dmg` into Applications. Requires **Apple Silicon (M1+) and macOS 14+**. Liquid Glass requires macOS 26+. Runtime validated on macOS 27.2.

**Signing:** ad-hoc signed app, installer without Developer ID, and no Apple notarization. macOS may require “Open Anyway” under Privacy & Security. Do not disable Gatekeeper.

The queue and history are session-only. Format/codec availability depends on the source; video is remuxed without re-encoding. Read the [English README](https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP/blob/main/README.en.md).

### Assets

- `.pkg`: macOS graphical installer / instalador gráfico.
- `.dmg`: drag-to-Applications disk image / imagem para arrastar até Aplicativos.
- `.zip`: the standalone app / aplicativo portátil.
- `ThirdPartySources.tar.gz`: corresponding sources for bundled multimedia components / fontes correspondentes.
- `SHA256SUMS.txt`: artifact integrity checksums / checksums dos arquivos.
