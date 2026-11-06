# Backend do webapp

FastAPI no Render, diretório raiz `backend`, Dockerfile `Dockerfile`. Frontend estático na Vercel com raiz `webapp`. Ambos usam a branch `codex/ytdlp-webapp`.

Variáveis somente no Render: `APP_PASSWORD`, `SESSION_SECRET`, `ALLOWED_ORIGIN=https://ytdlp-tau.vercel.app` e `RAPIDAPI_KEY` (IG Downloader API / apisales). Não use a chave no frontend ou em variáveis públicas.

O webapp exige a senha privada existente. A Vercel encaminha `/api/*` ao Render, mantendo o cookie HttpOnly/Secure/SameSite=Lax na mesma origem, inclusive no Safari do iPad.

Instagram é exclusivo do webapp: `POST /api/instagram/stories` consulta perfil público, retorna uma lista de prévias, guarda os URLs no servidor por 10 minutos e reutiliza a consulta nesse período. `POST /api/instagram/downloads` recebe somente o identificador da lista e os IDs selecionados (até 50) e cria uma tarefa individual para cada mídia. Nenhum login/cookie pessoal do Instagram é usado. Outros links continuam no yt-dlp.

Limites locais: até 900 consultas por mês UTC por armazenamento do servidor, 150 MB por mídia e 2 tarefas simultâneas. O Basic da API tem limite rígido de 1.000 consultas/mês; a renovação do fornecedor pode diferir do mês UTC. O contador local e os arquivos são temporários no Render Free e podem se perder em reinícios/deploys; o limite do fornecedor continua sendo a referência. Não é necessário usar os URLs `get` da RapidAPI para transferir mídia.

Teste: `python -m unittest discover -s backend -v`. Para desenvolvimento na mesma origem, configure `WEBAPP_DIR` com o caminho absoluto de `webapp` e execute `uvicorn server:app` dentro de `backend`. A autenticação usa cookie Secure, portanto teste com HTTPS ou cliente de testes HTTPS.

Downloads concluídos e seus arquivos temporários são removidos 24 horas após a conclusão. O Render Free pode demorar para iniciar após inatividade; downloads e listas podem desaparecer antes disso em reinícios ou deploys. O app macOS funciona de forma local e não depende deste backend.
