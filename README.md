# claude-multi-instances

Rode múltiplas instâncias do **Claude Desktop**, do **Cursor** ou do **Codex CLI**
(macOS, Windows, Linux), cada uma logada em uma conta diferente (ex: empresa +
pessoal + freela).

## Instâncias

A lista de contas fica em um arquivo só: [`instances.conf`](./instances.conf).

```
claude:personal
claude:work
claude:freela
cursor:personal
cursor:freela
codex:personal
codex:work
```

Opcional, para o Raycast: `serviço:nome|Título|emoji`

```
claude:work|Claude (Work)|💼
```

Edite esse arquivo **ou** use `./setup` opção **1** (Configurar): no meio do
fluxo dá para criar uma conta nova na lista antes dos atalhos.

Isso é **aditivo**:

- Linha nova: cria pasta vazia + atalho. As contas que já existiam continuam intactas.
- Linha tirada do conf: some só o atalho. A pasta `~/.claude-instances/<nome>`
  (ou `~/.cursor-instances/<nome>`, `~/.codex-instances/<nome>`) **fica**.
- Recolocar o mesmo nome no conf: reusa a pasta. Login, Cowork, extensões voltam.
- `./setup` opção 2: apaga **só as contas que você escolher** (pasta + atalhos +
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

No **Codex CLI**, o estado inteiro mora em `CODEX_HOME` (default `~/.codex`):
`config.toml`, `auth.json`, sessões e logs. Sem um home por conta, os logins
se misturam.

## A solução

Claude e Cursor são apps Electron e aceitam `--user-data-dir`. Rodando com essa
flag, cada instância recebe seu **próprio sandbox**: config, sessão, tokens de
auth e, no Claude, o bundle da VM do Cowork.

No Cursor também passamos `--extensions-dir`, senão as extensões continuam
compartilhadas em `~/.cursor/extensions`.

O Codex **não** é Electron. Cada linha `codex:<nome>` vira
`~/.codex-instances/<nome>` exportado como `CODEX_HOME`. O setup cria
`codex_<nome>` no PATH (`codex_personal`, `codex_work`, …).

```bash
open -n -a "/Applications/Claude.app" --args --user-data-dir="$HOME/.claude-instances/personal"

open -n -a "/Applications/Cursor.app" --args \
  --user-data-dir="$HOME/.cursor-instances/personal" \
  --extensions-dir="$HOME/.cursor-instances/personal/extensions"

mkdir -p "$HOME/.codex-instances/personal"
CODEX_HOME="$HOME/.codex-instances/personal" codex
```

Créditos pela descoberta original (Claude): [philippstracker.com/multiple-claude-instances](https://philippstracker.com/multiple-claude-instances/)

## Setup

Um script só. Ele detecta o SO e pergunta o que fazer (Claude, Cursor, Codex ou
todos; Raycast, Spotlight, etc.).

```bash
./setup
```

Menu inicial:

1. **Configurar Nova Instancia** — pastas e logins que já existem não são apagados.
2. **Apagar Instância** — exige confirmação (`apagar`).
3. **Sair**

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

No macOS a pergunta **Como você quer abrir as instâncias isoladas?** importa:

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

Se existirem atalhos **nossos** na Área de Trabalho (`Claude (nome).command` e
equivalentes) e você não escolheu “Área de Trabalho” nesta rodada, o setup
apaga só esses arquivos. Não mexe em outros arquivos da mesa.

Os scripts em `scripts/macos/`, `scripts/linux/` e `scripts/windows/` continuam
funcionando se você quiser chamá-los direto.

### Importar o perfil padrão

Na **primeira vez** de uma instância (pasta ainda vazia), o configurar pergunta
se quer copiar o perfil do app original (Dock) para ela. O original não é
apagado. Instâncias que já têm login não são oferecidas (não sobrescreve).
Caches ficam de fora; no Claude a VM do Cowork (`vm_bundles`) entra na cópia.
No Codex o `auth.json` **não** é copiado.

Enter ou `n` deixam a pasta vazia para você logar do zero.

Para copiar depois, sem refazer launchers (só destinos ainda vazios):

```bash
./scripts/import.sh
./scripts/import.sh cursor
./scripts/import.sh codex
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

### Codex

O Codex isolado é a CLI (`codex`), não o ChatGPT.app. Cada instância usa
`CODEX_HOME=~/.codex-instances/<nome>`. O setup instala um comando no PATH
(`~/.local/bin`) com o nome que você escolheu:

```bash
codex_personal
codex_work
```

Não cria atalho de Raycast/Spotlight. `codex_personal login` entra naquela
conta. Equivalente manual: `CODEX_HOME="$HOME/.codex-instances/personal" codex`.

Faça `codex_<nome> login` **em cada conta**. Não copie `auth.json` do `~/.codex`: o
refresh OAuth é de uso único; a cópia morre no próximo refresh. O import copia
`config.toml`, sessões e histórico, e **exclui** `auth.json`.

Não use `~/.codex` e uma pasta isolada ao mesmo tempo com o mesmo login. Se
ligar Keychain (`cli_auth_credentials_store = "keyring"`), a entrada já é
por hash do `CODEX_HOME` — também isolada. `CODEX_API_KEY` /
`OPENAI_API_KEY` no ambiente ainda vazam para todas as instâncias.

`--profile` no Codex não isola conta. `CODEX_BIN` aponta para o binário se
ele não estiver no PATH.

## Remover

Há dois significados de “remover”:

1. **Só o atalho** — tire a linha do `instances.conf` e rode `./setup`. Atalhos
   nossos que sobrarem na Área de Trabalho saem no próximo configurar (se você
   não pediu mesa nesta rodada). Os dados isolados ficam.
2. **Dados de verdade** — `./setup` opção 2. Lista as contas do
   `instances.conf`; você escolhe quais (ex.: `1` ou `1,3`). O script mostra
   os caminhos e só segue se você digitar `apagar`. Apaga a pasta isolada, os
   atalhos daquela conta e a linha no conf. As outras instâncias não são
   tocadas. Recriar o mesmo nome no conf começa vazio.

**Não** desinstala o app e **não** mexe no perfil padrão. Pastas isoladas que
não estão no conf também ficam.

```bash
./setup                          # opção 2, menu interativo
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
   (no Claude, a VM do Cowork leva ~1-2 GB na primeira vez; no Codex, rode
   `codex_<nome> login`).
5. Feche, abra a próxima e logue com as outras fechadas. Deep links
   `claude://` abrem na última instância que os registrou.
6. Depois de logadas, pode deixar várias abertas ao mesmo tempo.

## Pré-requisitos

### macOS
- Claude Desktop em `/Applications/Claude.app` e/ou Cursor em
  `/Applications/Cursor.app` (ou `CLAUDE_APP_PATH` / `CURSOR_APP_PATH`)
- Codex: binário `codex` no PATH (ou `CODEX_BIN`)
- [Raycast](https://raycast.com), se for usar `setup-raycast.sh`
- Nenhuma permissão especial (Acessibilidade/Automação) é necessária

### Windows
- Claude Desktop em `%LOCALAPPDATA%\Programs\Claude` e/ou Cursor em
  `%LOCALAPPDATA%\Programs\cursor`
- Codex: `codex` no PATH (ou `CODEX_BIN`)
- PowerShell 5.0+

### Linux
- Executáveis `claude`, `cursor` e/ou `codex` no PATH, ou as variáveis `*_APP_PATH` / `CODEX_BIN`
- Bash

## Aviso

Claude e Cursor usam flags não documentadas oficialmente do Electron / VS Code.
Funciona hoje, mas pode quebrar em atualizações futuras do app. O Codex usa
`CODEX_HOME`, que a CLI trata como home de auth/config.

## Licença

MIT — veja [LICENSE](./LICENSE).
