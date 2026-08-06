#!/bin/bash
# setup-linux-launchers.sh
#
# Cria atalhos .desktop na Área de Trabalho do Linux para rodar múltiplas
# instâncias isoladas do Claude Desktop (uma por conta), cada uma com seu
# próprio --user-data-dir. Isso dá a cada instância um sandbox completo
# (config, VM do Cowork, MCPs, sessão, tokens de auth), então features
# como o Cowork funcionam normalmente em todas.
#
# Uso:
#   chmod +x setup-linux-launchers.sh
#   ./setup-linux-launchers.sh
#
# Edite a lista INSTANCE_NAMES abaixo para os nomes/quantidade de contas
# que você quer.

set -e

# Ajuste para a localização onde você instalou Claude (flatpak, snap, /opt, etc.)
# Comum: /usr/bin/claude, ~/.local/bin/claude, ~/Applications/claude, ou como flatpak
APP_PATH="${CLAUDE_APP_PATH:-/usr/bin/claude}"
INSTANCES_BASE="$HOME/.claude-instances"
DESKTOP_DIR="$HOME/Desktop"

INSTANCE_NAMES=("work" "personal")

if [ ! -x "$APP_PATH" ]; then
  echo "Não encontrei Claude executável em $APP_PATH"
  echo "Ajuste a variável APP_PATH ou CLAUDE_APP_PATH no topo do script."
  echo ""
  echo "Localizações comuns:"
  echo "  /usr/bin/claude"
  echo "  ~/.local/bin/claude"
  echo "  ~/Applications/Claude"
  echo "  ~/.var/app/com.anthropic.Claude/bin/claude  (flatpak)"
  exit 1
fi

mkdir -p "$DESKTOP_DIR" "$INSTANCES_BASE"

for name in "${INSTANCE_NAMES[@]}"; do
  instance_dir="$INSTANCES_BASE/$name"
  mkdir -p "$instance_dir"

  desktop_path="$DESKTOP_DIR/Claude ($name).desktop"

  cat > "$desktop_path" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Claude ($name)
Comment=Instância isolada do Claude Desktop ($name)
Exec=$APP_PATH --user-data-dir="$instance_dir"
Icon=com.anthropic.Claude
Terminal=false
Categories=Development;
EOF

  chmod +x "$desktop_path"
  echo "Criado: $desktop_path -> dados em $instance_dir"
done

echo ""
echo "Pronto. Na Área de Trabalho agora existem:"
for name in "${INSTANCE_NAMES[@]}"; do
  echo "  - Claude ($name).desktop"
done
echo ""
echo "IMPORTANTE:"
echo "1. Feche TODAS as janelas/instâncias do Claude antes de logar em uma nova."
echo "2. Clique em 'Claude (work).desktop', faça login na conta da empresa,"
echo "   espere o Cowork terminar de montar o ambiente (VM ~1-2GB na primeira vez)."
echo "3. Feche essa instância, depois clique em 'Claude (personal).desktop' e logue na"
echo "   conta pessoal. Cada uma tem seu próprio sandbox, então o Cowork deve"
echo "   funcionar normalmente nas duas."
echo "4. Depois de logado, pode abrir as duas ao mesmo tempo sem conflito."
