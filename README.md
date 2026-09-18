# claude-multi-instances

Rode múltiplas instâncias do **Claude Desktop** ou do **Cursor** (macOS, Windows,
Linux), cada uma logada em uma conta diferente (ex: empresa + pessoal + freela).

## Instâncias

A lista de contas fica em um arquivo só: [`instances.conf`](./instances.conf).

```
claude:personal
claude:work
claude:freela
cursor:personal
cursor:freela
```

Opcional, para o Raycast: `serviço:nome|Título|emoji`

```
claude:work|Claude (Work)|💼
```

Edite esse arquivo **ou** use `./setup` opção **2** (Adicionar instância).
A opção **1** (Configurar) também pergunta se você quer acrescentar uma conta
antes de criar os atalhos.

Isso é **aditivo**:

- Linha nova: cria pasta vazia + atalho. As contas que já existiam continuam intactas.
- Linha tirada do conf: some só o atalho. A pasta `~/.claude-instances/<nome>`
  (ou `~/.cursor-instances/<nome>`) **fica**.
- Recolocar o mesmo nome no conf: reusa a pasta. Login, Cowork, extensões voltam.
- `./setup` opção 4: apaga **só as contas que você escolher** (pasta + atalhos +
  linha do conf). Recriar o nome começa do zero.

## O problema

Esses apps normalmente permitem apenas uma conta logada por vez em uma máquina.

No **Claude Desktop**, truques como symlinks ou mover a pasta de dados entre
contas quebram o Cowork:

- **macOS**: A VM roda em Apple Virtualization/VirtioFS, presa à pasta de dados padrão.
  Symlinks quebram a resolução de path do VirtioFS, e mover a pasta enquanto o app
  está aberto causa race condition de locks de arquivo.
- **Windows e Linux**: O Cowork não consegue funcionar corretamente se a pasta de dados
  mudar ou ficar inacessível, o que acontece quando trocamos de conta.

No **Cursor**, a mesma pasta de dados concentra login, settings, histórico e
extensões. Sem isolamento, duas contas brigam pelo mesmo perfil.

## A solução

Os dois são apps Electron e aceitam `--user-data-dir`. Rodando com essa flag,
cada instância recebe seu **próprio sandbox**: config, sessão, tokens de auth
e, no Claude, o bundle da VM do Cowork.

No Cursor também passamos `--extensions-dir`, senão as extensões continuam
compartilhadas em `~/.cursor/extensions`.

```bash
open -n -a "/Applications/Claude.app" --args --user-data-dir="$HOME/.claude-instances/personal"

open -n -a "/Applications/Cursor.app" --args \
  --user-data-dir="$HOME/.cursor-instances/personal" \
  --extensions-dir="$HOME/.cursor-instances/personal/extensions"
```

Créditos pela descoberta original (Claude): [philippstracker.com/multiple-claude-instances](https://philippstracker.com/multiple-claude-instances/)

## Setup

Um script só. Ele detecta o SO e pergunta o que fazer (Claude, Cursor ou ambos;
Raycast, Spotlight, etc.).

```bash
./setup
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

No macOS a pergunta **Como você abre os apps?** importa:

- **Raycast** — Script Commands. Cadastre `~/.claude-instances/raycast-scripts`
  uma vez em Preferências → Extensions → Script Commands.
- **Spotlight** — cria mini-apps em `~/Applications` (`Cursor (Personal)`,
  `Claude (Work)`, …). Cmd+Espaço busca esses nomes. **Não precisa de Raycast.**
- **Raycast e Spotlight** — os dois.
- **Área de Trabalho** — arquivos `.command`. Opcionais; não são necessários
  se você usa Raycast ou Spotlight.
- **Só pastas** — isola os dados, sem atalho nenhum.

O cubo/ícone original no Dock continua sendo o perfil padrão. A instância
isolada é o item do Raycast/Spotlight com o nome da conta.

Se já existirem `.command` na Área de Trabalho e você não escolher essa opção,
o setup pergunta se quer apagá-los (os dados isolados ficam). Também dá para
só limpar a mesa: `./setup` → opção 3.

Os scripts em `scripts/macos/`, `scripts/linux/` e `scripts/windows/` continuam
funcionando se você quiser chamá-los direto.

### Importar o perfil padrão

No final do setup o script pergunta, **por serviço**, para quais instâncias copiar
os dados do app original (Dock). O menu segue as contas do `instances.conf`:

```
Quer colocar os dados do Claude padrão (~13G) em:
  1) Somente no personal  (já tem dados)
  2) Somente no work
  3) Todas as instâncias vazias (não mexe nas que já têm dados)
  4) Não importar
Várias: 1,3
```

Enter ou a última opção pulam. “Todas as vazias” **não** sobrescreve instâncias
que já têm login/Cowork. Escolher o número de um destino já populado pede
confirmação (default: manter). Caches ficam de fora; no Claude a VM do Cowork
(`vm_bundles`) entra na cópia.

Para importar depois, sem refazer launchers:

```bash
./scripts/import.sh
./scripts/import.sh cursor
```

Windows: `scripts/import.ps1`. Para setup sem pergunta: `SKIP_IMPORT=1 ./scripts/macos/setup-desktop.sh`.

Fecha a instância que estiver usando a pasta de origem ou de destino (lock
file). Rodar o setup de dentro do Cursor isolado costuma ser ok, desde que o
perfil padrão e o destino da cópia não estejam abertos.

### Cursor

O app original e o perfil padrão (`~/Library/Application Support/Cursor`,
`~/.cursor`) não são alterados. O ícone do Dock e o comando `cursor` continuam
abrindo o perfil original; use os launchers (ou o Raycast) para as contas
isoladas.

Alguns paths do Cursor (`~/.cursor/agents`, `~/.cursor/rules`) ainda não
respeitam `--user-data-dir` e ficam compartilhados entre instâncias.

## Remover

Há dois significados de “remover”:

1. **Só o atalho** — tire a linha do `instances.conf` e rode `./setup`, ou use
   a opção 3 para os `.command` da Área de Trabalho. Os dados isolados ficam.
2. **Dados de verdade** — `./setup` opção 4. Lista as contas do
   `instances.conf`; você escolhe quais (ex.: `1` ou `1,3`). O script mostra
   os caminhos e só segue se você digitar `apagar`. Apaga a pasta isolada, os
   atalhos daquela conta e a linha no conf. As outras instâncias não são
   tocadas. Recriar o mesmo nome no conf começa vazio.

**Não** desinstala o app e **não** mexe no perfil padrão. Pastas isoladas que
não estão no conf também ficam.

```bash
./setup                          # opção 4, menu interativo
./scripts/remove.sh              # o mesmo menu
./scripts/remove.sh claude:personal cursor:work
./scripts/remove.sh claude       # todas as contas Claude do conf
./scripts/remove.sh all
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/remove.ps1
powershell -ExecutionPolicy Bypass -File scripts/remove.ps1 -Instance claude:personal
powershell -ExecutionPolicy Bypass -File scripts/remove.ps1 -Service claude
powershell -ExecutionPolicy Bypass -File scripts/remove.ps1 -Service all
```

`--yes` / `-Yes` pula a confirmação `apagar`. Se o Raycast ainda listar os
Script Commands, remova o diretório em Preferências → Extensions → Script
Commands.

## Como usar (primeira vez)

1. Edite [`instances.conf`](./instances.conf).
2. Feche completamente as janelas do app.
3. Rode o setup da sua plataforma.
4. Abra a primeira instância, faça login, espere o ambiente ficar pronto
   (no Claude, a VM do Cowork leva ~1-2 GB na primeira vez).
5. Feche, abra a próxima e logue com as outras fechadas. Deep links
   `claude://` abrem na última instância que os registrou.
6. Depois de logadas, pode deixar várias abertas ao mesmo tempo.

## Pré-requisitos

### macOS
- Claude Desktop em `/Applications/Claude.app` e/ou Cursor em
  `/Applications/Cursor.app` (ou `CLAUDE_APP_PATH` / `CURSOR_APP_PATH`)
- [Raycast](https://raycast.com), se for usar `setup-raycast.sh`
- Nenhuma permissão especial (Acessibilidade/Automação) é necessária

### Windows
- Claude Desktop em `%LOCALAPPDATA%\Programs\Claude` e/ou Cursor em
  `%LOCALAPPDATA%\Programs\cursor`
- PowerShell 5.0+

### Linux
- Executáveis `claude` e/ou `cursor` no PATH, ou as variáveis `*_APP_PATH`
- Bash

## Aviso

Isso usa flags não documentadas oficialmente do Electron / VS Code. Funciona
hoje, mas pode quebrar em atualizações futuras do app.

## Licença

MIT — veja [LICENSE](./LICENSE).
