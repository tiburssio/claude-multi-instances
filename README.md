# claude-multi-instances

Rode múltiplas instâncias do **Claude Desktop** no macOS, cada uma logada em
uma conta diferente (ex: empresa + pessoal), com **Cowork funcionando
normalmente em todas elas**.

## O problema

O Claude Desktop normalmente permite apenas uma conta logada por vez. Truques
como symlinks ou mover a pasta de dados entre contas quebram o Cowork, porque
ele roda uma VM local (Apple Virtualization/VirtioFS) que fica presa à pasta
de dados padrão do app:

- **Symlinks** quebram a resolução de path do VirtioFS quando a VM tenta
  montar o disco.
- **Mover a pasta** enquanto o app está aberto causa race condition, já que a
  VM mantém locks de arquivo nos discos dentro dela.

## A solução

O Claude Desktop é um app Electron, então aceita a flag `--user-data-dir`.
Rodando com essa flag, cada instância recebe seu **próprio sandbox completo e
isolado**: config, bundle da VM, MCPs, dados de sessão e tokens de auth. Como
cada instância tem sua própria VM, o Cowork funciona normalmente em todas,
inclusive rodando ao mesmo tempo.

```bash
open -n -a "/Applications/Claude.app" --args --user-data-dir="$HOME/.claude-instances/personal"
```

Créditos pela descoberta original: [philippstracker.com/multiple-claude-instances](https://philippstracker.com/multiple-claude-instances/)

## Scripts disponíveis

### `scripts/setup-desktop-launchers.sh`

Cria arquivos `.command` clicáveis na Área de Trabalho (um por conta). Dê
duplo clique para abrir a instância correspondente.

```bash
chmod +x scripts/setup-desktop-launchers.sh
./scripts/setup-desktop-launchers.sh
```

### `scripts/setup-raycast-scripts.sh`

Cria [Script Commands](https://developers.raycast.com/basics/create-your-first-script-command)
do [Raycast](https://raycast.com), para abrir cada instância direto da busca
do Raycast, sem precisar de ícones na Área de Trabalho.

```bash
chmod +x scripts/setup-raycast-scripts.sh
./scripts/setup-raycast-scripts.sh
```

Depois, no Raycast: **Preferências → Extensions → Script Commands → "+" → Add
Script Directory**, e aponte para `~/.claude-instances/raycast-scripts`. As
ações aparecem buscando por "Claude".

## Como usar (primeira vez)

1. Feche completamente todas as janelas/instâncias do Claude abertas.
2. Rode o script de sua preferência (acima).
3. Abra a primeira instância (ex: "Claude (Work)"), faça login com a conta
   correspondente e espere o Cowork terminar de montar o ambiente — a VM leva
   ~1-2 GB e alguns minutos na primeira vez.
4. Feche essa instância, abra a próxima (ex: "Claude (Personal)") e faça login
   com as outras fechadas. Deep links `claude://` sempre abrem na última
   instância que os registrou, então evite ter duas abertas durante o login.
5. Depois de logadas as duas, pode deixar ambas abertas ao mesmo tempo sem
   conflito.

## Pré-requisitos

- macOS
- Claude Desktop instalado em `/Applications/Claude.app` (ajuste `APP_PATH`
  no topo do script se instalou em outro lugar)
- [Raycast](https://raycast.com) instalado, se for usar
  `setup-raycast-scripts.sh` (a extensão nativa Script Commands já vem
  habilitada)
- Nenhuma permissão especial do macOS (Acessibilidade/Automação) é necessária

## Personalizando

Edite a lista de instâncias no topo de cada script (`INSTANCE_NAMES` ou
`INSTANCES`) para adicionar mais contas, mudar nomes ou ícones.

## Aviso

Isso usa uma flag não documentada oficialmente do Electron/Claude Desktop.
Funciona hoje, mas pode quebrar em atualizações futuras do app.

## Licença

MIT — veja [LICENSE](./LICENSE).
