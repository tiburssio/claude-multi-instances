#!/bin/bash
# setup-raycast-scripts.sh
#
# Cria Script Commands do Raycast para abrir instâncias isoladas do
# Claude Desktop (uma por conta), cada uma com seu próprio
# --user-data-dir, sem precisar de arquivos na Área de Trabalho.
#
# Uso:
#   chmod +x setup-raycast-scripts.sh
#   ./setup-raycast-scripts.sh
#
# Depois, no Raycast: Preferências > Extensions > Script Commands > "+"
# > Add Script Directory, e aponte para: ~/.claude-instances/raycast-scripts
# As ações aparecem na busca do Raycast como "Claude (Work)" e "Claude (Personal)".

set -e

APP_PATH="/Applications/Claude.app"
INSTANCES_BASE="$HOME/.claude-instances"
SCRIPTS_DIR="$INSTANCES_BASE/raycast-scripts"

# Cada entrada: nome-interno|Título no Raycast|emoji do ícone
INSTANCES=(
  "work|Claude (Work)|💼"
  "personal|Claude (Personal)|🏠"
)

if [ ! -d "$APP_PATH" ]; then
  echo "Não encontrei $APP_PATH. Ajuste a variável APP_PATH no topo do script."
  exit 1
fi

mkdir -p "$SCRIPTS_DIR"

for entry in "${INSTANCES[@]}"; do
  IFS="|" read -r name title icon <<< "$entry"
  instance_dir="$INSTANCES_BASE/$name"
  mkdir -p "$instance_dir"

  script_path="$SCRIPTS_DIR/claude-$name.sh"

  cat > "$script_path" <<EOF
#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title $title
# @raycast.mode silent

# Optional parameters:
# @raycast.icon $icon
# @raycast.packageName Claude Instances

# Documentation:
# @raycast.description Abre a instância isolada do Claude Desktop ($name)
# @raycast.author Alexandre

open -n -a "$APP_PATH" --args --user-data-dir="$instance_dir"
EOF

  chmod +x "$script_path"
  echo "Criado: $script_path  -> dados em $instance_dir"
done

echo ""
echo "Pasta de scripts: $SCRIPTS_DIR"
echo ""
echo "Agora no Raycast:"
echo "1. Abra Raycast > Preferências (Cmd+,) > Extensions > Script Commands."
echo "2. Clique em '+' > 'Add Script Directory' e selecione:"
echo "   $SCRIPTS_DIR"
echo "3. As ações vão aparecer buscando por 'Claude' no Raycast."
echo ""
echo "IMPORTANTE:"
echo "- Feche todas as instâncias abertas do Claude antes de logar em uma nova."
echo "- Na primeira vez que abrir cada instância, faça login e espere o Cowork"
echo "  terminar de montar o ambiente (VM ~1-2GB)."
echo "- Depois de logadas, pode manter as duas abertas ao mesmo tempo."
