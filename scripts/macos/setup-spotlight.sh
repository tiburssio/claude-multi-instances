#!/bin/bash
# Cria mini-apps em ~/Applications para o Spotlight (Cmd+Espaço).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh"

FILTER="$(parse_optional_service_arg "${1:-}")"
load_instances "$FILTER"

APPS_DIR="$(macos_apps_dir)"
mkdir -p "$APPS_DIR"

lsregister() {
  local tool="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [ -x "$tool" ]; then
    "$tool" -f "$1" >/dev/null 2>&1 || true
  fi
}

first_icns() {
  ls "$1/Contents/Resources/"*.icns 2>/dev/null | head -1
}

bundle_id_for() {
  local service="$1" name="$2"
  local slug
  slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')"
  printf 'local.instances.%s.%s' "$service" "$slug"
}

create_app_bundle() {
  local display_name="$1" bundle_id="$2" launch_line="$3" src_app="$4" dest="$5"
  local macos_dir resources_dir icns icon_name
  macos_dir="$dest/Contents/MacOS"
  resources_dir="$dest/Contents/Resources"
  mkdir -p "$macos_dir" "$resources_dir"

  cat > "$macos_dir/launcher" <<EOF
#!/bin/bash
$launch_line
EOF
  chmod +x "$macos_dir/launcher"

  icon_name=""
  icns="$(first_icns "$src_app" || true)"
  if [ -n "$icns" ]; then
    cp "$icns" "$resources_dir/AppIcon.icns"
    icon_name="AppIcon"
  fi

  cat > "$dest/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$display_name</string>
  <key>CFBundleDisplayName</key>
  <string>$display_name</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleExecutable</key>
  <string>launcher</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
EOF
  if [ -n "$icon_name" ]; then
    cat >> "$dest/Contents/Info.plist" <<EOF
  <key>CFBundleIconFile</key>
  <string>$icon_name</string>
EOF
  fi
  cat >> "$dest/Contents/Info.plist" <<EOF
</dict>
</plist>
EOF

  lsregister "$dest"
}

created=0
skipped_services=""
created_services=""

for i in "${!INSTANCE_NAMES[@]}"; do
  service="${INSTANCE_SERVICES[$i]}"
  name="${INSTANCE_NAMES[$i]}"
  label="$(service_label "$service")"
  app_path="$(service_macos_app_path "$service")"
  instance_dir="$(service_instances_base "$service")/$name"
  display_name="$label ($name)"
  dest="$APPS_DIR/$display_name.app"
  icon_src="$app_path"
  if [ "$service" = "codex" ]; then
    for terminal_app in \
      "/System/Applications/Utilities/Terminal.app" \
      "/Applications/Utilities/Terminal.app"
    do
      if [ -d "$terminal_app" ]; then
        icon_src="$terminal_app"
        break
      fi
    done
  fi

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
  create_app_bundle "$display_name" "$(bundle_id_for "$service" "$name")" "$launch_line" "$icon_src" "$dest"
  echo "Criado: $dest  -> dados em $instance_dir"
  created=$((created + 1))
  created_services="$(list_add "$created_services" "$service")"
done

if [ "$created" -eq 0 ]; then
  die "Nenhum app do Spotlight criado."
fi

for service in $created_services; do
  label="$(service_label "$service")"
  keep_names=()
  while IFS= read -r name; do
    [ -n "$name" ] && keep_names+=("$name")
  done < <(names_for_service "$service")
  prune_stale_apps "$APPS_DIR" "$label" "${keep_names[@]}"
done

echo ""
echo "Pronto. No Spotlight (Cmd+Espaço) busque pelo nome da instância:"
for i in "${!INSTANCE_NAMES[@]}"; do
  service="${INSTANCE_SERVICES[$i]}"
  list_has "$created_services" "$service" || continue
  echo "  - $(service_label "$service") (${INSTANCE_NAMES[$i]})"
done
echo "Os apps ficam em $APPS_DIR — não na Área de Trabalho."
echo "O ícone original no Dock continua sendo o perfil padrão."
if list_has "$created_services" codex; then
  echo "Codex abre o Terminal com CODEX_HOME na pasta da instância."
fi
echo ""
echo "Lista de contas: $INSTANCES_CONF"

prompt_and_import_for_services "$created_services"
