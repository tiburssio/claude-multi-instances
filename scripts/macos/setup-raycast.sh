#!/bin/bash
# Cria Script Commands do Raycast a partir de instances.conf.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh"

FILTER="$(parse_optional_service_arg "${1:-}")"
load_instances "$FILTER"

created=0
skipped_services=""
created_services=""
scripts_dir="$(raycast_scripts_dir)"
mkdir -p "$scripts_dir"

for i in "${!INSTANCE_NAMES[@]}"; do
  service="${INSTANCE_SERVICES[$i]}"
  name="${INSTANCE_NAMES[$i]}"
  title="${INSTANCE_TITLES[$i]}"
  icon="${INSTANCE_ICONS[$i]}"
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
  if [ "$service" = "codex" ] && [ ! -x "$instance_dir/launch.command" ]; then
    echo "Não consegui criar o runner do Codex em $instance_dir"
    continue
  fi

  launch_line="$(macos_launch_line "$service" "$app_path" "$instance_dir")"
  launch_line="${launch_line%$'\n'}"
  script_path="$scripts_dir/$service-$name.sh"

  cat > "$script_path" <<EOF
#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title $title
# @raycast.mode silent

# Optional parameters:
# @raycast.icon $icon
# @raycast.packageName $label Instances
# @raycast.keywords $service, $name, instance

# Documentation:
# @raycast.description Abre a instância isolada $service:$name
# @raycast.author Alexandre

$launch_line
EOF

  chmod +x "$script_path"
  echo "Criado: $script_path  -> dados em $instance_dir"
  created=$((created + 1))
  created_services="$(list_add "$created_services" "$service")"
done

if [ "$created" -eq 0 ]; then
  die "Nenhum script do Raycast criado."
fi

echo ""
for service in $created_services; do
  keep_names=()
  while IFS= read -r name; do
    [ -n "$name" ] && keep_names+=("$name")
  done < <(names_for_service "$service")
  prune_stale_raycast "$scripts_dir" "$service" "${keep_names[@]}"
done

echo "Pasta de Script Commands: $scripts_dir"
echo ""
echo "No Raycast (só precisa cadastrar essa pasta uma vez):"
echo "1. Preferências (Cmd+,) → Extensions → Script Commands."
echo "2. '+' → Add Script Directory → $scripts_dir"
echo "3. Busque por Claude, Cursor ou Codex. As instâncias aparecem como"
echo "   'Cursor (Personal)', 'Claude (Work)', 'Codex (Work)', etc."
echo ""
echo "Lista de contas: $INSTANCES_CONF"
if list_has "$created_services" cursor; then
  echo "O Dock e o comando 'cursor' continuam no perfil original."
fi
if list_has "$created_services" codex; then
  echo "Codex no Raycast abre o Terminal (TUI). Faça login em cada instância."
fi

prompt_and_import_for_services "$created_services"
