# YTDLP Studio — revisão visual

Aplicativo nativo para organizar downloads em lote. O elemento central é a relação entre links e resultado: links à esquerda, opções de saída à direita e atividade logo abaixo. Em janelas compactas, as duas áreas empilham e continuam acessíveis por rolagem.

## Direção aplicada

- Fundo: material `hudWindow`, `behindWindow`, aparência `darkAqua`. A janela tem `isOpaque = false`, fundo transparente e camada preta com 64% de opacidade adicional, conforme o pedido de transparência escura e discreta.
- Superfícies de conteúdo: fundo semântico `windowBackgroundColor` com 68% de opacidade; contorno reforçado quando o sistema solicita maior contraste. Sem Liquid Glass nos cards ou nas linhas.
- Navegação: três abas nativas no topo; Liquid Glass nos botões de ação no macOS 26+. Os controles recebem feedback de pressionar, foco e ponteiro do sistema.
- Tipografia: SF do sistema. Título 30 pt semibold, seções 15 pt semibold, corpo 13–14 pt, metadados 11–12 pt. As cores de texto são semânticas e respondem à aparência escura.
- Cor: destaque do sistema para iniciar e acompanhar o download; falhas têm símbolo/texto além de cor.
- Acessibilidade: foco do teclado nos links, nomes para controles com ícones, atalhos de navegação, fundo sólido ao reduzir transparência e transição sem movimento ao reduzir animações.
- Conteúdo: codecs e seletor manual ficam em uma seção expansível; a tabela de formatos informa os dados reais da fonte, incluindo valores não informados pelo site.

## Fontes aplicadas

- [Apple Design de Emil Kowalski](https://www.ui-skills.com/skills/emilkowalski/apple-design): materiais e profundidade, resposta imediata, movimento reduzido e tipografia.
- Skill local Apple Design: `liquid-glass.md › The two layers`, `materials.md › Standard materials`, `layout.md › Visual hierarchy`, `tab-bars.md › Best practices`, `typography.md › Ensuring legibility` e `accessibility.md › Mobility`.

A aparência escura foi fixada por pedido explícito do usuário. O vidro do fundo usa material padrão do AppKit; a refração Liquid Glass fica na navegação e nas ações. As capturas de uma janela isolada podem não reproduzir todo o conteúdo visto por trás dela na composição da área de trabalho.

## Verificação

Compilação arm64, assinatura ad hoc, verificação de bundle, abertura nativa e inspeção visual. Pela interface: consulta de formatos de uma mídia sintética local, seleção, início via ⌘↵, conclusão e acesso ao Finder. No núcleo: 12 verificações de comandos/seletores e integração com fila de três vídeos, dois processos simultâneos, consulta real de formatos e conversões para as 12 opções de áudio oferecidas. Sem promessa de disponibilidade de um codec ou qualidade que o site não fornece.
