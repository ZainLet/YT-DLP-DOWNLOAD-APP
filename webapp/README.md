# YTDLP Studio Web

Frontend responsivo para iPad, preparado para deploy como site estático na Vercel.

## Estado atual

- Interface baseada no YTDLP Studio nativo.
- Layout adaptado para toque e telas pequenas.
- Abas Baixar / Atividade / Concluídos.
- Formulário de vídeo/áudio, formato, qualidade e opções avançadas.
- Fila demonstrativa com progresso local.
- Integração real ainda pendente: o frontend usa `demoMode` em `app.js` até existir um backend privado que execute `yt-dlp` e `FFmpeg`.

## Deploy na Vercel

No projeto da Vercel, configure o diretório raiz como `webapp` e deixe o framework como **Other**. Não é necessário comando de build para esta primeira versão.

## Contrato planejado do backend

`POST /api/downloads`

```json
{
  "links": ["https://..."],
  "options": {"kind":"video","container":"mp4","quality":"1080p"}
}
```

Resposta esperada: `{ "jobs": [{ "id": "...", "status": "queued" }] }`.

Depois, o frontend poderá acompanhar cada item por `GET /api/downloads/:id` ou por SSE/WebSocket e receber uma URL temporária para o arquivo concluído.
