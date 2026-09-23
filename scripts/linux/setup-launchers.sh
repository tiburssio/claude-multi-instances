#!/bin/bash
# Cria atalhos .desktop na Área de Trabalho a partir de instances.conf.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh"

FILTER="$(parse_optional_service_arg "${1:-}")"
load_instances "$FILTER"

LAUNCHER_DIR="${LAUNCHER_DIR:-$HOME/Desktop}"
mkdir -p "$LAUNCHER_DIR"

created=0
skipped_services=""
created_services=""

for i in "${!INSTANCE_NAMES[@]}"; do
  service="${INSTANCE_SERVICES[$i]}"
  name="${INSTANCE_NAMES[$i]}"
  label="$(service_label "$service")"
  instance_dir="$(service_instances_base "$service")/$name"
  app_path="$(resolve_linux_app_path "$service" || true)"

  if [ -z "$app_path" ] || [ ! -x "$app_path" ]; then
    if ! list_has "$skipped_services" "$service"; then
      echo "Executável não encontrado: $service"
      skipped_services="$(list_add "$skipped_services" "$service")"
    fi
    continue
  fi

  prepare_instance_dir "$service" "$instance_dir"
  if [ "$service" = "codex" ] && [ ! -x "$instance_dir/run" ]; then
    echo "Não consegui criar o runner do Codex em $instance_dir"
    continue
  fi
  desktop_path="$LAUNCHER_DIR/$label ($name).desktop"
  exec_args="$(linux_exec_args "$service" "$instance_dir")"
  icon="$(service_linux_icon "$service")"
  comment="$(service_linux_comment "$service" "$name")"
  if [ "$service" = "codex" ]; then
    exec_line="\"$instance_dir/run\""
    terminal="true"
  else
    exec_line="$app_path $exec_args"
    terminal="false"
  fi

  cat > "$desktop_path" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$label ($name)
Comment=$comment
Exec=$exec_line
Icon=$icon
Terminal=$terminal
Categories=Development;
EOF

  chmod +x "$desktop_path"
  echo "Criado: $desktop_path -> dados em $instance_dir"
  created=$((created + 1))
  created_services="$(list_add "$created_services" "$service")"
done

if [ "$created" -eq 0 ]; then
  echo "Defina CLAUDE_APP_PATH / CURSOR_APP_PATH / CODEX_BIN se o binário não estiver no PATH."
  die "Nenhum launcher criado."
fi

for service in $created_services; do
  label="$(service_label "$service")"
  keep_names=()
  while IFS= read -r name; do
    [ -n "$name" ] && keep_names+=("$name")
  done < <(names_for_service "$service")
  prune_stale_launchers "$LAUNCHER_DIR" "$label" "${keep_names[@]}"
done

echo ""
echo "Pronto. Atalhos em $LAUNCHER_DIR:"
for i in "${!INSTANCE_NAMES[@]}"; do
  service="${INSTANCE_SERVICES[$i]}"
  list_has "$created_services" "$service" || continue
  echo "  - $(service_label "$service") (${INSTANCE_NAMES[$i]}).desktop"
done

echo ""
echo "IMPORTANTE:"
echo "- Feche todas as janelas do app antes de logar em uma instância nova."
echo "- Logue uma conta por vez. Depois de logadas, podem ficar abertas juntas."
if list_has "$created_services" claude; then
  echo "- Claude: na primeira vez, espere o Cowork montar a VM (~1-2 GB)."
fi
if list_has "$created_services" cursor; then
  echo "- Cursor: o atalho original continua no perfil padrão."
fi
if list_has "$created_services" codex; then
  echo "- Codex: abre um terminal com CODEX_HOME na pasta da instância."
  echo "- Codex: faça login em cada pasta. Não copie auth.json."
fi
echo "- Lista de contas: $INSTANCES_CONF"

prompt_and_import_for_services "$created_services"
