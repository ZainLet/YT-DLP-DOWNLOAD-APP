# YTDLP Studio Web

Site privado responsivo para iPad, hospedado na Vercel (`ytdlp1/ytdlp`, raiz `webapp`, framework Other, sem build).

Abas Baixar, Instagram, Atividade e Concluídos. No Instagram, informe um perfil público ou link de Story, liste as prévias e marque somente as mídias desejadas. Na fila, toque em Preparar arquivos e depois em Salvar na galeria para abrir o menu de compartilhamento, quando o navegador permitir. No iPad, escolha Salvar vídeos ou Salvar imagens para adicionar à galeria, se disponível. Cada item também pode ser salvo individualmente. O lote reúne somente os arquivos já concluídos da seleção mais recente e limita o tamanho total a 200 MB.

`vercel.json` encaminha `/api/*` ao backend Render. A chave da RapidAPI fica exclusivamente nas variáveis do Render. Veja `../backend/README.md` para configuração, limites e testes.

A integração do Instagram pertence apenas ao webapp. O app macOS mantém Baixar, Atividade e Concluídos com yt-dlp local.
