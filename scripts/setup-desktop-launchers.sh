#!/bin/bash
# setup-desktop-launchers.sh
#
# Cria launchers clicáveis na Área de Trabalho para rodar múltiplas
# instâncias isoladas do Claude Desktop no macOS (uma por conta), cada
# uma com seu próprio --user-data-dir. Isso dá a cada instância um
# sandbox completo (config, VM do Cowork, MCPs, sessão, tokens de auth),
# então features como o Cowork funcionam normalmente em todas.
#
# Baseado em:
# https://philippstracker.com/multiple-claude-instances/
#
# Uso:
#   chmod +x setup-desktop-launchers.sh
#   ./setup-desktop-launchers.sh
#
# Edite a lista INSTANCE_NAMES abaixo para os nomes/quantidade de contas
# que você quer.

set -e

APP_PATH="/Applications/Claude.app"
INSTANCES_BASE="$HOME/.claude-instances"
DESKTOP_DIR="$HOME/Desktop"

INSTANCE_NAMES=("work" "personal")

if [ ! -d "$APP_PATH" ]; then
  echo "Não encontrei $APP_PATH. Ajuste a variável APP_PATH no topo do script."
  exit 1
fi

mkdir -p "$INSTANCES_BASE"

for name in "${INSTANCE_NAMES[@]}"; do
  instance_dir="$INSTANCES_BASE/$name"
  mkdir -p "$instance_dir"

  launcher_path="$DESKTOP_DIR/Claude ($name).command"

  cat > "$launcher_path" <<EOF
#!/bin/bash
# Launcher isolado para a conta: $name
# Diretório de dados: $instance_dir
open -n -a "$APP_PATH" --args --user-data-dir="$instance_dir"
EOF

  chmod +x "$launcher_path"
  echo "Criado: $launcher_path  -> dados em $instance_dir"
done

echo ""
echo "Pronto. No Finder (Desktop) agora existem:"
for name in "${INSTANCE_NAMES[@]}"; do
  echo "  - Claude ($name).command"
done
echo ""
echo "IMPORTANTE:"
echo "1. Feche TODAS as janelas/instâncias do Claude antes de logar em uma nova."
echo "2. Dê duplo clique em 'Claude (work).command', faça login na conta da empresa,"
echo "   espere o Cowork terminar de montar o ambiente (VM ~1-2GB na primeira vez)."
echo "3. Feche essa instância, depois abra 'Claude (personal).command' e logue na"
echo "   conta pessoal. Cada uma tem seu próprio sandbox, então o Cowork deve"
echo "   funcionar normalmente nas duas."
echo "4. Depois de logado, pode abrir as duas ao mesmo tempo sem conflito."
