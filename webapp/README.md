# YTDLP Studio Web

Site privado responsivo para iPad, hospedado na Vercel (`ytdlp1/ytdlp`, raiz `webapp`, framework Other, sem build).

Abas Baixar, Instagram, Atividade e Concluídos. No Instagram, informe um perfil público ou link de Story, liste as prévias e marque somente as mídias desejadas. Toque em Baixar selecionados e depois em Salvar para cada arquivo na fila.

`vercel.json` encaminha `/api/*` ao backend Render. A chave da RapidAPI fica exclusivamente nas variáveis do Render. Veja `../backend/README.md` para configuração, limites e testes.

A integração do Instagram pertence apenas ao webapp. O app macOS mantém Baixar, Atividade e Concluídos com yt-dlp local.
