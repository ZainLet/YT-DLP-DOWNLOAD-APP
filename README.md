<div align="center">
  <img src="assets/AppIcon.png" width="104" alt="Ícone do YTDLP Studio">
  <h1>YTDLP Studio</h1>
  <p>Vídeos e músicas, do link para o seu Mac.</p>
  <p><strong>Português</strong> · <a href="README.en.md">English</a></p>
  <p><a href="https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP/releases/latest">Baixar para macOS</a> · <a href="https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP/releases">Beta para Windows</a> · <a href="#instalação">Instalação</a> · <a href="#compilar-a-partir-do-código">Compilar</a></p>
</div>

Aplicativo nativo para macOS feito com SwiftUI e AppKit. Organiza downloads em lote do [yt-dlp](https://github.com/yt-dlp/yt-dlp) em uma janela com fundo escuro translúcido, desfoque nativo e controles Liquid Glass.

## Instalação

1. Abra a [última release](https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP/releases/latest).
2. Baixe `YTDLP-Studio-1.2.0-macOS-arm64.pkg` e siga o instalador. Ele coloca o app em **Aplicativos**.
3. Como alternativa, baixe o `.dmg`, abra a imagem e arraste **YTDLP Studio** para **Applications**.
4. Abra **YTDLP Studio** em Aplicativos ou pelo Spotlight.

O instalador inclui **yt-dlp, FFmpeg, FFprobe e Deno**. Não é necessário instalar Python, Homebrew ou abrir um terminal para usar a versão distribuída. A versão `.zip` contém o mesmo app para instalação manual.

**Assinatura desta release:** o app tem assinatura local ad hoc; o instalador não possui certificado Developer ID e a release não é notarizada pela Apple. O macOS pode bloquear a primeira abertura. Depois de conferir a origem e o checksum, use **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**, se a opção estiver disponível. Não desative o Gatekeeper. Organizações que exigem notarização podem impedir a execução desta versão.

### Requisitos

| Item | Requisito |
| --- | --- |
| Mac | Apple Silicon: M1 ou posterior |
| Sistema | macOS 14 ou posterior |
| Liquid Glass | macOS 26 ou posterior; controles padrão nas versões anteriores |
| Conexão | Internet para acessar as mídias |
| Espaço | App, ferramentas incluídas e espaço livre para seus downloads |

O binário distribuído é **arm64**. Não há uma versão Intel nesta release. O runtime foi validado no macOS 27.2; o alvo mínimo de compilação é macOS 14.

### Beta para Windows

Uma versão beta nativa para **Windows 10 versão 22H2 (build 19045) e Windows 11 x64** está disponível na [página de releases](https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP/releases). O instalador inclui o app e as ferramentas necessárias; também há uma versão portátil. Esta beta ainda precisa ser testada em computadores Windows. Consulte as instruções e limitações nas notas da release.

## O que o app faz

- Adiciona vários links de uma vez, um por linha.
- Executa até **dois downloads simultâneos**, com fila para os próximos.
- Separa **Baixar**, **Atividade** e **Concluídos** em abas nativas.
- Mostra título, progresso, velocidade, tempo restante, cancelamento e falhas.
- Permite escolher a pasta de destino e localizar o arquivo concluído no Finder.
- Consulta os formatos reais do primeiro link em **Formatos do link…**.
- Oferece filtros de resolução, FPS, codecs, qualidade de áudio e seleção manual por ID.
- Usa transparência escurecida e desfoque, com adaptação a **Reduzir Transparência** e **Reduzir Movimento** do macOS.

### Formatos e qualidade

| Categoria | Opções |
| --- | --- |
| Vídeo | Original, MP4, MKV, WebM, MOV, AVI, FLV, GIF |
| Áudio | Original, MP3, M4A, AAC, Opus, OGG/Vorbis, FLAC, ALAC, WAV, AIFF, MKA |
| Resolução máxima | Melhor disponível, 8K, 4K, 1440p, 1080p, 720p, 480p, 360p, 240p, 144p |
| FPS máximo | Automático, 120, 60, 50, 30, 25, 24 |
| Qualidade de áudio | VBR 0–10 e bitrates de 64 a 320 kbps |
| Codecs de vídeo da fonte | Automático, H.264/AVC, H.265/HEVC, AV1, VP9, VP8, MPEG-4, MPEG-2, Theora, ProRes |
| Codecs de áudio da fonte | Automático, AAC, Opus, Vorbis, MP3, FLAC, ALAC, PCM, AC3, EAC3, DTS |

As opções dependem do que o site fornece. Um filtro de codec **seleciona uma faixa da fonte**; ele não recodifica o vídeo. A troca de contêiner de vídeo usa remux e pode falhar se o contêiner não suportar os codecs selecionados. Áudio pode ser convertido pelo FFmpeg; escolher FLAC ou WAV não recupera qualidade perdida na origem. Bitrate não se aplica aos formatos sem perdas da mesma forma que aos formatos com perdas.

Para controle completo, use **Formatos do link…** ou o **seletor yt-dlp** em opções avançadas. Exemplos: `137+140`, `bv+ba/b`. O seletor manual substitui os filtros automáticos de resolução e codec. A tabela não inclui storyboards sem áudio/vídeo.

## Como usar

1. Na aba **Baixar**, cole um ou mais links HTTP/HTTPS, um por linha.
2. Escolha **Vídeo** ou **Áudio**, formato, qualidade e destino.
3. Abra **Codecs e opções avançadas** se precisar filtrar as faixas da fonte.
4. Clique em **Iniciar download** ou pressione **⌘ Return**.
5. Acompanhe em **Atividade**. Os arquivos finalizados aparecem em **Concluídos**.

| Atalho | Ação |
| --- | --- |
| ⌘ N | Ir para um novo download |
| ⌘ 1 / ⌘ 2 / ⌘ 3 | Baixar / Atividade / Concluídos |
| ⌘ Return | Iniciar o lote de links |

## Dados e limites atuais

- O app não tem backend hospedado nem conta própria. As ferramentas acessam diretamente os sites dos links informados.
- A fila e o histórico são mantidos **apenas na sessão**. Fechar o app não preserva a lista; os arquivos já baixados permanecem no disco.
- Cada link é tratado como um item; expansão automática de playlists está desativada.
- A interface desta versão está em português; esta documentação também está disponível [em inglês](README.en.md).
- Conteúdos com DRM, login obrigatório, restrições regionais ou mudanças nos sites podem não funcionar. Não há integração de login/cookies na interface.
- Baixe apenas conteúdo que você possui ou tem autorização para salvar.

## Compilar a partir do código

Requer Apple Silicon, Xcode 26 ou posterior e suas ferramentas de linha de comando.

```bash
git clone https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP.git
cd YT-DLP-DOWNLOAD-APP
bash build_mac_app.sh
open "YTDLP Studio.app"
```

O build de desenvolvimento usa as ferramentas disponíveis no `PATH`. Para esse modo, instale `yt-dlp`, `ffmpeg` e `deno`, por exemplo com `brew install yt-dlp ffmpeg deno`.

### Build completo do instalador

Requer também `make`, `clang`, `pkg-config`, `curl`, `tar` e as ferramentas de empacotamento do macOS. `pkg-config` pode ser instalado com `brew install pkgconf`.

```bash
bash scripts/prepare_runtime.sh
STUDIO_BUNDLE_TOOLS=1 bash build_mac_app.sh
bash scripts/package_release.sh
bash scripts/check_release.sh
```

O runtime usa versões fixadas e confere os downloads com `packaging/runtime-downloads.sha256`. FFmpeg e suas bibliotecas são compilados a partir das fontes, com vínculo estático e sem componentes GPL/nonfree. Os artefatos ficam em `dist/`: `.pkg`, `.dmg`, `.zip`, fontes de terceiros e `SHA256SUMS.txt`. Nenhum script do instalador baixa ou instala componentes adicionais no sistema.

Para verificar os arquivos de uma release, coloque os artefatos e `SHA256SUMS.txt` na mesma pasta e execute `shasum -a 256 -c SHA256SUMS.txt`.

### Verificações

```bash
mkdir -p .build/ModuleCache
xcrun swiftc macOS/Sources/DownloadCore.swift macOS/Tests/DownloadCoreChecks.swift \
  -parse-as-library -o .build/download-checks -module-cache-path .build/ModuleCache
.build/download-checks
```

O teste de integração aceita a URL de um servidor local com `sample1.mp4`, `sample2.mp4`, `sample3.mp4`, seguida de uma pasta de destino. Ele verifica concorrência, fila, arquivos finais, consulta de formatos e as 12 opções de áudio. A release também é verificada quanto à assinatura local, integridade e ausência de vínculos com bibliotecas do Homebrew.

## Estrutura

```text
macOS/Sources/          App, interface e núcleo de downloads
macOS/Tests/            Verificações dos comandos e da fila
assets/                Ícone do aplicativo
packaging/             Configuração e conteúdo do instalador
scripts/               Runtime portátil, empacotamento e verificação
build_mac_app.sh        Compilação do .app
```

## Terceiros e créditos

O app usa [yt-dlp](https://github.com/yt-dlp/yt-dlp), [FFmpeg](https://ffmpeg.org), [Deno](https://deno.com), LAME e bibliotecas Xiph. Consulte [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) para versões, licenças, fontes correspondentes e instruções para substituir os componentes. O arquivo de fontes correspondente é publicado ao lado do instalador na mesma release.

Design desenvolvido com referências das Human Interface Guidelines da Apple. Este projeto é independente e não é afiliado à Apple nem ao projeto yt-dlp.
