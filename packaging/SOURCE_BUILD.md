# Rebuilding the bundled multimedia tools

1. Clone `https://github.com/ZainLet/YT-DLP-DOWNLOAD-APP` and check out tag `v1.2.0`.
2. Extract `YTDLP-Studio-1.2.0-ThirdPartySources.tar.gz` into a temporary directory.
3. In the repository, create `.build/runtime/sources` and copy the supplied `.tar.gz` and `.tar.xz` source archives there.
4. Install the build prerequisites documented in the English or Portuguese README.
5. Run `bash scripts/prepare_runtime.sh`. The script verifies the source archives against the committed checksum file, builds static libraries, and compiles FFmpeg/FFprobe with the exact flags used in this release. It downloads the pinned yt-dlp and Deno standalone executables if not cached.
6. The rebuilt tools appear under `.build/runtime/bin`. Replace the app's `Contents/Resources/Tools/ffmpeg` and `ffprobe` with your modified builds. Re-sign the binaries and the outer app locally using `codesign --force --sign -` to maintain macOS bundle integrity.

No source patches are applied. The script overrides an obsolete compiler flag from the libvorbis configure script through the make command line. All multimedia-library sources used for this release are provided in this archive. The archive also includes yt-dlp's source and upstream third-party license notices.

The standalone app communicates with the multimedia programs through command-line arguments and pipes. It does not link to these libraries. You may replace the tools or modify their sources under their respective licenses. No signing key from this project is required for local replacement.

Em português: clone o repositório na tag `v1.2.0`, copie os arquivos-fonte fornecidos para `.build/runtime/sources` e execute o script indicado. Os binários recompilados podem substituir as ferramentas dentro do aplicativo. Os pré-requisitos estão descritos nos dois READMEs. A assinatura ad hoc pode ser recriada localmente, sem uma chave do projeto.
