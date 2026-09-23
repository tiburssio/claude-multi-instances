#!/bin/bash
# Cria launchers .command na Área de Trabalho a partir de instances.conf.

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
  app_path="$(service_macos_app_path "$service")"
  instance_dir="$(service_instances_base "$service")/$name"

  if ! macos_service_ready "$service"; then
    if ! list_has "$skipped_services" "$service"; then
      if [ "$service" = "codex" ]; then
        echo "codex não encontrado no PATH"
      else
        echo "App não encontrado: $app_path ($service)"
      fi
      skipped_services="$(list_add "$skipped_services" "$service")"
    fi
    continue
  fi

  prepare_instance_dir "$service" "$instance_dir"
  if [ "$service" = "codex" ] && [ ! -x "$instance_dir/run" ]; then
    echo "Não consegui criar o runner do Codex em $instance_dir"
    continue
  fi
  launcher_path="$LAUNCHER_DIR/$label ($name).command"
  if [ "$service" = "codex" ]; then
    cat > "$launcher_path" <<EOF
#!/bin/bash
# Launcher isolado: $service:$name
# Diretório de dados: $instance_dir
exec "$instance_dir/run" "\$@"
EOF
  else
    launch_line="$(macos_launch_line "$service" "$app_path" "$instance_dir")"
    launch_line="${launch_line%$'\n'}"
    cat > "$launcher_path" <<EOF
#!/bin/bash
# Launcher isolado: $service:$name
# Diretório de dados: $instance_dir
$launch_line
EOF
  fi

  chmod +x "$launcher_path"
  echo "Criado: $launcher_path  -> dados em $instance_dir"
  created=$((created + 1))
  created_services="$(list_add "$created_services" "$service")"
done

if [ "$created" -eq 0 ]; then
  if [ -n "$FILTER" ]; then
    echo "Ajuste CLAUDE_APP_PATH / CURSOR_APP_PATH / CODEX_BIN se instalou em outro lugar."
  fi
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
echo "Pronto. Launchers na Área de Trabalho:"
for i in "${!INSTANCE_NAMES[@]}"; do
  service="${INSTANCE_SERVICES[$i]}"
  list_has "$created_services" "$service" || continue
  echo "  - $(service_label "$service") (${INSTANCE_NAMES[$i]}).command"
done

echo ""
echo "IMPORTANTE:"
echo "- Feche todas as janelas do app antes de logar em uma instância nova."
echo "- Logue uma conta por vez. Depois de logadas, podem ficar abertas juntas."
if list_has "$created_services" claude; then
  echo "- Claude: na primeira vez, espere o Cowork montar a VM (~1-2 GB)."
  echo "- Deep links claude:// abrem na última instância que os registrou."
fi
if list_has "$created_services" cursor; then
  echo "- Cursor: o Dock e o comando 'cursor' continuam no perfil original."
fi
if list_has "$created_services" codex; then
  echo "- Codex: abre o TUI no Terminal com CODEX_HOME na pasta da instância."
  echo "- Codex: faça login em cada pasta (codex login). Não copie auth.json."
fi
echo "- Lista de contas: $INSTANCES_CONF"

prompt_and_import_for_services "$created_services"
