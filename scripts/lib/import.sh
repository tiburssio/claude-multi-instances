# Importa o perfil padrão (Dock) para instâncias isoladas.
# Requer que common.sh já tenha sido carregado.

service_default_user_data_dir() {
  local service="$1"
  case "$(detect_os)" in
    macos)
      case "$service" in
        claude) echo "$HOME/Library/Application Support/Claude" ;;
        cursor) echo "$HOME/Library/Application Support/Cursor" ;;
        *) die "Serviço desconhecido: $service" ;;
      esac
      ;;
    windows)
      case "$service" in
        claude) echo "${APPDATA:-$HOME/AppData/Roaming}/Claude" ;;
        cursor) echo "${APPDATA:-$HOME/AppData/Roaming}/Cursor" ;;
        *) die "Serviço desconhecido: $service" ;;
      esac
      ;;
    *)
      case "$service" in
        claude) echo "$HOME/.config/Claude" ;;
        cursor) echo "$HOME/.config/Cursor" ;;
        *) die "Serviço desconhecido: $service" ;;
      esac
      ;;
  esac
}

service_default_extensions_dir() {
  case "$1" in
    cursor) echo "$HOME/.cursor/extensions" ;;
    claude) echo "" ;;
    *) die "Serviço desconhecido: $1" ;;
  esac
}

instance_has_profile_data() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  [ -f "$dir/Cookies" ] && return 0
  [ -f "$dir/config.json" ] && return 0
  [ -f "$dir/claude_desktop_config.json" ] && return 0
  [ -f "$dir/User/settings.json" ] && return 0
  [ -d "$dir/User" ] && return 0
  [ -d "$dir/vm_bundles" ] && return 0
  [ -d "$dir/Local Storage" ] && return 0
  [ -d "$dir/IndexedDB" ] && return 0
  return 1
}

instance_dir() {
  echo "$(service_instances_base "$1")/$2"
}

confirm_overwrite_instance() {
  local name="$1" ans
  printf "%s já tem dados isolados. Sobrescrever com o perfil padrão? [y/N] " "$name"
  read -r ans || true
  case "$(trim "$ans")" in
    y|Y|yes|YES|s|S|sim|Sim) return 0 ;;
    *) return 1 ;;
  esac
}

profile_is_locked() {
  local dir="$1"
  [ -e "$dir/SingletonLock" ] || [ -L "$dir/SingletonLock" ] || [ -e "$dir/SingletonSocket" ]
}

ensure_profiles_unlocked() {
  local again dir any
  while true; do
    any=0
    for dir in "$@"; do
      if profile_is_locked "$dir"; then
        if [ "$any" -eq 0 ]; then
          echo ""
          echo "Feche o app que está usando estas pastas (lock file):"
        fi
        echo "  $dir"
        any=1
      fi
    done
    if [ "$any" -eq 0 ]; then
      return 0
    fi
    printf "Enter para tentar de novo, n para cancelar: "
    read -r again || true
    case "$(trim "$again")" in
      n|N|nao|não|Nao|Não) return 1 ;;
    esac
  done
}

rsync_profile() {
  local src="$1" dest="$2"
  if ! command -v rsync >/dev/null 2>&1; then
    die "rsync não encontrado. Instale rsync para importar o perfil."
  fi
  mkdir -p "$dest"
  rsync -a \
    --exclude 'Cache/' \
    --exclude 'CachedData/' \
    --exclude 'CachedExtensionVSIXs/' \
    --exclude 'Code Cache/' \
    --exclude 'GPUCache/' \
    --exclude 'DawnGraphiteCache/' \
    --exclude 'DawnWebGPUCache/' \
    --exclude 'Crashpad/' \
    --exclude 'logs/' \
    --exclude 'SingletonLock' \
    --exclude 'SingletonSocket' \
    --exclude 'SingletonCookie' \
    "$src/" "$dest/"
}

import_default_to_instance() {
  local service="$1" name="$2"
  local src dest ext_src ext_dest
  src="$(service_default_user_data_dir "$service")"
  dest="$(service_instances_base "$service")/$name"

  echo "Copiando perfil padrão → $service:$name"
  echo "  de: $src"
  echo "  para: $dest"
  prepare_instance_dir "$service" "$dest"
  rsync_profile "$src" "$dest"

  ext_src="$(service_default_extensions_dir "$service")"
  if [ -n "$ext_src" ] && [ -d "$ext_src" ]; then
    ext_dest="$dest/extensions"
    mkdir -p "$ext_dest"
    echo "  extensões: $ext_src → $ext_dest"
    rsync -a "$ext_src/" "$ext_dest/"
  fi
  echo "Pronto: $service:$name"
}

prompt_and_import_default_data() {
  local service="$1"
  local names=() n i count all_n skip_n src size ans chosen idx
  local dest_names=() lock_dirs=()

  if [ "${SKIP_IMPORT:-}" = "1" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    return 0
  fi

  while IFS= read -r n; do
    [ -n "$n" ] && names+=("$n")
  done < <(names_for_service "$service")
  count=${#names[@]}
  if [ "$count" -eq 0 ]; then
    return 0
  fi

  src="$(service_default_user_data_dir "$service")"
  if [ ! -d "$src" ]; then
    echo "Perfil padrão do $(service_label "$service") não encontrado ($src). Pulando import."
    return 0
  fi

  all_n=$((count + 1))
  skip_n=$((count + 2))
  size="$(du -sh "$src" 2>/dev/null | awk '{print $1}')"

  echo ""
  echo "Quer colocar os dados do $(service_label "$service") padrão (~$size) em:"
  i=0
  while [ "$i" -lt "$count" ]; do
    n="${names[$i]}"
    if instance_has_profile_data "$(instance_dir "$service" "$n")"; then
      echo "  $((i + 1))) Somente no $n  (já tem dados)"
    else
      echo "  $((i + 1))) Somente no $n"
    fi
    i=$((i + 1))
  done
  echo "  $all_n) Todas as instâncias vazias (não mexe nas que já têm dados)"
  echo "  $skip_n) Não importar"
  echo "Várias: 1,3"
  echo ""
  echo "O perfil original não é apagado. Setup nunca apaga pastas de instâncias existentes."

  while true; do
    ans="$(ask "Escolha [$skip_n]: ")"
    chosen=$(parse_numbered_pick "$ans" "$count") || continue
    break
  done

  if [ -z "$chosen" ]; then
    echo "Import do $(service_label "$service") pulado."
    return 0
  fi

  dest_names=()
  if [ "$chosen" = "__ALL__" ]; then
    for n in "${names[@]}"; do
      if instance_has_profile_data "$(instance_dir "$service" "$n")"; then
        echo "Mantendo $service:$n (já tem dados)."
        continue
      fi
      dest_names+=("$n")
    done
  else
    while IFS= read -r idx; do
      [ -n "$idx" ] || continue
      n="${names[$idx]}"
      if instance_has_profile_data "$(instance_dir "$service" "$n")"; then
        if confirm_overwrite_instance "$n"; then
          dest_names+=("$n")
        else
          echo "Mantendo $service:$n."
        fi
        continue
      fi
      dest_names+=("$n")
    done <<EOF
$chosen
EOF
  fi

  if [ "${#dest_names[@]}" -eq 0 ]; then
    echo "Nada para importar."
    return 0
  fi

  lock_dirs=("$src")
  for n in "${dest_names[@]}"; do
    lock_dirs+=("$(instance_dir "$service" "$n")")
  done

  if ! ensure_profiles_unlocked "${lock_dirs[@]}"; then
    echo "Import do $(service_label "$service") cancelado."
    return 0
  fi

  for n in "${dest_names[@]}"; do
    import_default_to_instance "$service" "$n"
  done
}

prompt_and_import_for_services() {
  local service
  for service in $1; do
    [ -n "$service" ] || continue
    prompt_and_import_default_data "$service"
  done
}
