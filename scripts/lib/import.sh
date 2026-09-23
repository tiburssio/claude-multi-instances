# Importa o perfil padrão (Dock) para instâncias isoladas.
# Requer que common.sh já tenha sido carregado.

service_default_user_data_dir() {
  local service="$1"
  case "$(detect_os)" in
    macos)
      case "$service" in
        claude) echo "$HOME/Library/Application Support/Claude" ;;
        cursor) echo "$HOME/Library/Application Support/Cursor" ;;
        codex) echo "$HOME/.codex" ;;
        *) die "Serviço desconhecido: $service" ;;
      esac
      ;;
    windows)
      case "$service" in
        claude) echo "${APPDATA:-$HOME/AppData/Roaming}/Claude" ;;
        cursor) echo "${APPDATA:-$HOME/AppData/Roaming}/Cursor" ;;
        codex) echo "$HOME/.codex" ;;
        *) die "Serviço desconhecido: $service" ;;
      esac
      ;;
    *)
      case "$service" in
        claude) echo "$HOME/.config/Claude" ;;
        cursor) echo "$HOME/.config/Cursor" ;;
        codex) echo "$HOME/.codex" ;;
        *) die "Serviço desconhecido: $service" ;;
      esac
      ;;
  esac
}

service_default_extensions_dir() {
  case "$1" in
    cursor) echo "$HOME/.cursor/extensions" ;;
    claude|codex) echo "" ;;
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
  [ -f "$dir/config.toml" ] && return 0
  [ -f "$dir/auth.json" ] && return 0
  [ -f "$dir/history.jsonl" ] && return 0
  [ -d "$dir/sessions" ] && return 0
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
  shift 2
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
    "$@" \
    "$src/" "$dest/"
}

import_default_to_instance() {
  local service="$1" name="$2"
  local src dest ext_src ext_dest
  src="$(service_default_user_data_dir "$service")"
  dest="$(service_instances_base "$service")/$name"

  say "Copiando perfil padrão → $service:$name"
  say "  de: $src"
  say "  para: $dest"
  prepare_instance_dir "$service" "$dest"
  case "$service" in
    codex)
      rsync_profile "$src" "$dest" --exclude 'auth.json'
      write_codex_runner "$dest" >/dev/null 2>&1 || true
      say "  auth.json não copiado (refresh OAuth é de uso único)."
      say "  Nesta instância: $(codex_shim_name "$name") login"
      say "  Não use ~/.codex e esta pasta ao mesmo tempo com o mesmo login."
      ;;
    *)
      rsync_profile "$src" "$dest"
      ;;
  esac

  ext_src="$(service_default_extensions_dir "$service")"
  if [ -n "$ext_src" ] && [ -d "$ext_src" ]; then
    ext_dest="$dest/extensions"
    mkdir -p "$ext_dest"
    say "  extensões: $ext_src → $ext_dest"
    rsync -a "$ext_src/" "$ext_dest/"
  fi
  say "Pronto: $service:$name"
}

prompt_and_import_default_data() {
  local service="$1"
  local names=() empty=() n src dest_names=() lock_dirs=()

  if [ "${SKIP_IMPORT:-}" = "1" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    return 0
  fi

  while IFS= read -r n; do
    [ -n "$n" ] && names+=("$n")
  done < <(names_for_service "$service")
  if [ "${#names[@]}" -eq 0 ]; then
    return 0
  fi

  for n in "${names[@]}"; do
    if ! instance_has_profile_data "$(instance_dir "$service" "$n")"; then
      empty+=("$n")
    fi
  done
  if [ "${#empty[@]}" -eq 0 ]; then
    return 0
  fi

  src="$(service_default_user_data_dir "$service")"
  if [ ! -d "$src" ]; then
    return 0
  fi

  dest_names=()
  for n in "${empty[@]}"; do
    case "$(ask "Copiar perfil original do $(service_label "$service") para $n? [y/N] ")" in
      y|Y|s|S|sim|Sim) dest_names+=("$n") ;;
    esac
  done

  if [ "${#dest_names[@]}" -eq 0 ]; then
    return 0
  fi

  lock_dirs=("$src")
  for n in "${dest_names[@]}"; do
    lock_dirs+=("$(instance_dir "$service" "$n")")
  done

  if ! ensure_profiles_unlocked "${lock_dirs[@]}"; then
    echo "Cópia do $(service_label "$service") cancelada."
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
