# YTDLP Studio Backend

API Dockerizada para o webapp. Executa `yt-dlp` e `FFmpeg` no Render, sem depender do Mac.

## Variáveis do Render

- `APP_PASSWORD`: senha compartilhada para acessar o app.
- `SESSION_SECRET`: string aleatória longa para assinar a sessão.
- `ALLOWED_ORIGIN`: `https://ytdlp-tau.vercel.app`.

O filesystem é temporário no plano gratuito. Os arquivos ficam disponíveis para baixar enquanto a instância estiver viva; a próxima etapa, se necessário, é adicionar R2/Blob para retenção durável.

## Endpoints

- `GET /health`
- `POST /api/auth/login`
- `GET /api/auth/session`
- `POST /api/downloads`
- `GET /api/downloads/:id`
- `GET /api/downloads/:id/file`
