# shared helpers for setup/remove scripts
# shellcheck shell=bash

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_LIB_DIR/../.." && pwd)"
INSTANCES_CONF="${INSTANCES_CONF:-$REPO_ROOT/instances.conf}"

INSTANCE_SERVICES=()
INSTANCE_NAMES=()
INSTANCE_TITLES=()
INSTANCE_ICONS=()

die() {
  echo "$*" >&2
  exit 1
}

list_has() {
  local haystack="$1" needle="$2"
  case " $haystack " in
    *" $needle "*) return 0 ;;
    *) return 1 ;;
  esac
}

list_add() {
  local haystack="$1" needle="$2"
  if list_has "$haystack" "$needle"; then
    printf '%s' "$haystack"
    return 0
  fi
  if [ -n "$haystack" ]; then
    printf '%s %s' "$haystack" "$needle"
  else
    printf '%s' "$needle"
  fi
}

validate_service() {
  case "$1" in
    claude|cursor) ;;
    *)
      die "Serviço desconhecido: $1"
      ;;
  esac
}

service_label() {
  case "$1" in
    claude) echo "Claude" ;;
    cursor) echo "Cursor" ;;
    *)
      die "Serviço desconhecido: $1"
      ;;
  esac
}

service_instances_base() {
  case "$1" in
    claude) echo "$HOME/.claude-instances" ;;
    cursor) echo "$HOME/.cursor-instances" ;;
    *)
      die "Serviço desconhecido: $1"
      ;;
  esac
}

# Uma pasta só: o Raycast não indexa Script Commands até a pasta estar
# cadastrada em Extensões → Script Commands. Reusa a pasta antiga do Claude
# se ela já existir, para não exigir um segundo "Add Script Directory".
raycast_scripts_dir() {
  if [ -n "${RAYCAST_SCRIPTS_DIR:-}" ]; then
    printf '%s' "$RAYCAST_SCRIPTS_DIR"
    return 0
  fi
  if [ -d "$HOME/.claude-instances/raycast-scripts" ]; then
    printf '%s' "$HOME/.claude-instances/raycast-scripts"
    return 0
  fi
  printf '%s' "$HOME/.instances/raycast-scripts"
}

service_macos_app_path() {
  case "$1" in
    claude) echo "${CLAUDE_APP_PATH:-/Applications/Claude.app}" ;;
    cursor) echo "${CURSOR_APP_PATH:-/Applications/Cursor.app}" ;;
    *)
      die "Serviço desconhecido: $1"
      ;;
  esac
}

service_linux_icon() {
  case "$1" in
    claude) echo "com.anthropic.Claude" ;;
    cursor) echo "cursor" ;;
    *)
      die "Serviço desconhecido: $1"
      ;;
  esac
}

service_linux_comment() {
  local service="$1" name="$2"
  case "$service" in
    claude) echo "Instância isolada do Claude Desktop ($name)" ;;
    cursor) echo "Instância isolada do Cursor ($name)" ;;
    *)
      die "Serviço desconhecido: $service"
      ;;
  esac
}

default_title() {
  local service="$1" name="$2"
  local first rest
  first="$(printf '%s' "$name" | cut -c1 | tr '[:lower:]' '[:upper:]')"
  rest="$(printf '%s' "$name" | cut -c2-)"
  echo "$(service_label "$service") (${first}${rest})"
}

default_icon() {
  local service="$1" name="$2"
  case "$name" in
    personal|home) echo "🏠" ;;
    work|empresa) echo "💼" ;;
    freela|freelance) echo "🛠️" ;;
    *)
      case "$service" in
        claude) echo "🤖" ;;
        cursor) echo "💻" ;;
        *)
          die "Serviço desconhecido: $service"
          ;;
      esac
      ;;
  esac
}

macos_launch_line() {
  local service="$1" app_path="$2" instance_dir="$3"
  case "$service" in
    claude)
      printf 'open -n -a "%s" --args --user-data-dir="%s"\n' "$app_path" "$instance_dir"
      ;;
    cursor)
      printf 'open -n -a "%s" --args --user-data-dir="%s" --extensions-dir="%s/extensions"\n' \
        "$app_path" "$instance_dir" "$instance_dir"
      ;;
    *)
      die "Serviço desconhecido: $service"
      ;;
  esac
}

linux_exec_args() {
  local service="$1" instance_dir="$2"
  case "$service" in
    claude)
      printf -- '--user-data-dir="%s"' "$instance_dir"
      ;;
    cursor)
      printf -- '--user-data-dir="%s" --extensions-dir="%s/extensions"' "$instance_dir" "$instance_dir"
      ;;
    *)
      die "Serviço desconhecido: $service"
      ;;
  esac
}

prepare_instance_dir() {
  local service="$1" instance_dir="$2"
  mkdir -p "$instance_dir"
  case "$service" in
    claude) ;;
    cursor) mkdir -p "$instance_dir/extensions" ;;
    *)
      die "Serviço desconhecido: $service"
      ;;
  esac
}

desktop_dirs() {
  local dirs=("$HOME/Desktop")
  if [ -d "$HOME/Área de Trabalho" ]; then
    dirs+=("$HOME/Área de Trabalho")
  fi
  printf '%s\n' "${dirs[@]}"
}

detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *)
      case "${OS:-}" in
        Windows_NT) echo windows ;;
        *) echo unknown ;;
      esac
      ;;
  esac
}

each_desktop_launcher() {
  local service="$1"
  local label desktop_dir launcher
  label="$(service_label "$service")"
  while IFS= read -r desktop_dir; do
    [ -d "$desktop_dir" ] || continue
    shopt -s nullglob
    for launcher in \
      "$desktop_dir/$label ("*.command \
      "$desktop_dir/$label ("*.desktop
    do
      echo "$launcher"
    done
    shopt -u nullglob
  done < <(desktop_dirs)
}

macos_apps_dir() {
  echo "${MACOS_APPS_DIR:-$HOME/Applications}"
}

each_spotlight_app() {
  local service="$1"
  local label app apps_dir
  label="$(service_label "$service")"
  apps_dir="$(macos_apps_dir)"
  [ -d "$apps_dir" ] || return 0
  shopt -s nullglob
  for app in "$apps_dir/$label ("*.app; do
    echo "$app"
  done
  shopt -u nullglob
}

prune_stale_apps() {
  local apps_dir="$1" label="$2"
  shift 2
  local keep_names=("$@")
  local app base name keep k

  [ -d "$apps_dir" ] || return 0
  shopt -s nullglob
  for app in "$apps_dir/$label ("*.app; do
    base="$(basename "$app")"
    name="$(launcher_name_from_filename "$base" "$label")"
    keep=0
    for k in "${keep_names[@]}"; do
      if [ "$k" = "$name" ]; then
        keep=1
        break
      fi
    done
    if [ "$keep" -eq 0 ]; then
      rm -rf "$app"
      echo "Removido (não está em instances.conf): $app"
    fi
  done
  shopt -u nullglob
}

remove_spotlight_apps_for_service() {
  local service="$1"
  local label apps_dir
  label="$(service_label "$service")"
  apps_dir="$(macos_apps_dir)"
  prune_stale_apps "$apps_dir" "$label"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

ask() {
  local prompt="$1"
  local ans
  printf "%s" "$prompt" >&2
  read -r ans || true
  trim "$ans"
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -gt 0 ]
}

# Itens 1..N; N+1 = todas; N+2 = pular.
# stdout: __ALL__, vazio, ou índices 0-based (um por linha).
parse_numbered_pick() {
  local answer="$1"
  local count="$2"
  local all_n skip_n wordcount token idx picked

  all_n=$((count + 1))
  skip_n=$((count + 2))
  answer="$(printf '%s' "$answer" | tr ',;' ' ')"
  answer="$(trim "$answer")"

  if [ -z "$answer" ]; then
    return 0
  fi
  case "$answer" in
    n|nao|não|cancelar|q) return 0 ;;
  esac

  wordcount="$(printf '%s' "$answer" | wc -w | tr -d ' ')"
  if [ "$wordcount" -eq 1 ]; then
    if ! is_positive_int "$answer"; then
      echo "Opção inválida: $answer" >&2
      return 1
    fi
    if [ "$answer" -eq "$skip_n" ]; then
      return 0
    fi
    if [ "$answer" -eq "$all_n" ]; then
      echo "__ALL__"
      return 0
    fi
    if [ "$answer" -ge 1 ] && [ "$answer" -le "$count" ]; then
      echo $((answer - 1))
      return 0
    fi
    echo "Opção inválida: $answer" >&2
    return 1
  fi

  picked=""
  for token in $answer; do
    if ! is_positive_int "$token" || [ "$token" -lt 1 ] || [ "$token" -gt "$count" ]; then
      echo "Opção inválida: $token" >&2
      return 1
    fi
    idx=$((token - 1))
    picked="$(list_add "$picked" "$idx")"
  done
  if [ -z "$picked" ]; then
    return 1
  fi
  for token in $picked; do
    echo "$token"
  done
}

instance_display_name() {
  printf '%s (%s)' "$(service_label "$1")" "$2"
}

each_instance_artifact() {
  local service="$1" name="$2"
  local display dest desktop_dir
  display="$(instance_display_name "$service" "$name")"
  dest="$(service_instances_base "$service")/$name"
  printf '%s\n' "$dest"
  printf '%s\n' "$(raycast_scripts_dir)/$service-$name.sh"
  printf '%s\n' "$(macos_apps_dir)/$display.app"
  printf '%s\n' "$HOME/.local/share/applications/$display.desktop"
  if [ -n "${APPDATA:-}" ]; then
    printf '%s\n' "$APPDATA/Microsoft/Windows/Start Menu/Programs/$display.lnk"
  fi
  while IFS= read -r desktop_dir; do
    printf '%s\n' "$desktop_dir/$display.command"
    printf '%s\n' "$desktop_dir/$display.desktop"
    printf '%s\n' "$desktop_dir/$display.lnk"
  done < <(desktop_dirs)
}

remove_desktop_launchers_for_service() {
  local service="$1"
  local label desktop_dir path
  label="$(service_label "$service")"
  while IFS= read -r desktop_dir; do
    [ -d "$desktop_dir" ] || continue
    shopt -s nullglob
    for path in \
      "$desktop_dir/$label ("*.command \
      "$desktop_dir/$label ("*.desktop
    do
      rm -f "$path"
      echo "Removido: $path"
    done
    shopt -u nullglob
  done < <(desktop_dirs)
}

remove_instance() {
  local service="$1" name="$2"
  local dest base scripts_dir path
  validate_service "$service"
  if [ -z "$name" ] || [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    die "Nome de instância inválido: '$name'"
  fi

  dest="$(service_instances_base "$service")/$name"
  base="$(service_instances_base "$service")"
  scripts_dir="$(raycast_scripts_dir)"
  if [ "$dest" = "$base" ] || [ "$dest" = "$scripts_dir" ] || [ "$dest" = "$HOME" ]; then
    die "Recusa apagar $dest"
  fi

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ "$path" = "$scripts_dir" ] && continue
    [ "$path" = "$base" ] && continue
    if [ -e "$path" ] || [ -L "$path" ]; then
      rm -rf "$path"
      echo "Removido: $path"
    fi
  done < <(each_instance_artifact "$service" "$name")
}

conf_line_instance_key() {
  local line="$1"
  local service_and_name service name
  line="${line%$'\r'}"
  line="$(trim "$line")"
  [ -z "$line" ] && return 1
  case "$line" in
    \#*) return 1 ;;
  esac
  if [[ "$line" == *"|"* ]]; then
    service_and_name="${line%%|*}"
  else
    service_and_name="$line"
  fi
  service_and_name="$(trim "$service_and_name")"
  [[ "$service_and_name" == *:* ]] || return 1
  service="$(trim "${service_and_name%%:*}")"
  name="$(trim "${service_and_name#*:}")"
  [ -n "$service" ] && [ -n "$name" ] || return 1
  printf '%s:%s' "$service" "$name"
}

remove_keys_from_instances_conf() {
  local tmp raw line key keep k
  [ "$#" -gt 0 ] || return 0
  tmp="$(mktemp "${TMPDIR:-/tmp}/instances.conf.XXXXXX")"
  while IFS= read -r raw || [ -n "$raw" ]; do
    keep=1
    if key="$(conf_line_instance_key "$raw")"; then
      for k in "$@"; do
        if [ "$key" = "$k" ]; then
          keep=0
          break
        fi
      done
    fi
    if [ "$keep" -eq 1 ]; then
      printf '%s\n' "$raw" >> "$tmp"
    fi
  done < "$INSTANCES_CONF"
  mv "$tmp" "$INSTANCES_CONF"
}

list_conf_keys() {
  local filter="${1:-}"
  local raw key service
  [ -f "$INSTANCES_CONF" ] || return 0
  while IFS= read -r raw || [ -n "$raw" ]; do
    if key="$(conf_line_instance_key "$raw")"; then
      service="${key%%:*}"
      if [ -n "$filter" ] && [ "$service" != "$filter" ]; then
        continue
      fi
      printf '%s\n' "$key"
    fi
  done < "$INSTANCES_CONF"
}

instance_key_exists() {
  local want="$1" key
  while IFS= read -r key; do
    [ "$key" = "$want" ] && return 0
  done < <(list_conf_keys)
  return 1
}

append_instance_to_conf() {
  local service="$1" name="$2"
  validate_service "$service"
  if [ -z "$name" ] || [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Nome inválido: '$name' (use letras, números, . _ -)" >&2
    return 1
  fi
  if instance_key_exists "$service:$name"; then
    echo "Já existe $service:$name em $INSTANCES_CONF" >&2
    return 1
  fi
  if [ -s "$INSTANCES_CONF" ] && [ "$(tail -c 1 "$INSTANCES_CONF" | wc -l | tr -d ' ')" -eq 0 ]; then
    printf '\n' >> "$INSTANCES_CONF"
  fi
  printf '%s:%s\n' "$service" "$name" >> "$INSTANCES_CONF"
}

print_conf_instances() {
  local filter="${1:-}"
  local key i=1
  echo "Contas em $INSTANCES_CONF:"
  if [ -z "$(list_conf_keys "$filter")" ]; then
    if [ -n "$filter" ]; then
      echo "  (nenhuma de $(service_label "$filter"))"
    else
      echo "  (nenhuma)"
    fi
    return 0
  fi
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    echo "  $i) $key"
    i=$((i + 1))
  done < <(list_conf_keys "$filter")
}

prompt_and_add_instances() {
  local filter="${1:-}"
  local service name dest ans

  if [ ! -t 0 ]; then
    return 0
  fi

  while true; do
    echo ""
    print_conf_instances "$filter"
    echo ""
    echo "  1) Adicionar instância"
    echo "  2) Seguir"
    ans="$(ask "Escolha [2]: ")"
    case "$ans" in
      ""|2) return 0 ;;
      1) ;;
      *)
        echo "Opção inválida."
        continue
        ;;
    esac

    if [ -n "$filter" ]; then
      service="$filter"
      echo "App: $(service_label "$service")"
    else
      echo ""
      echo "  1) Claude"
      echo "  2) Cursor"
      case "$(ask "App: ")" in
        1) service="claude" ;;
        2) service="cursor" ;;
        *)
          echo "Opção inválida."
          continue
          ;;
      esac
    fi

    name="$(ask "Nome da instância (ex: work, freela): ")"
    if ! append_instance_to_conf "$service" "$name"; then
      continue
    fi
    dest="$(service_instances_base "$service")/$name"
    echo "Adicionado $service:$name"
    echo "  conf: $INSTANCES_CONF"
    echo "  pasta (no configurar): $dest"
  done
}

load_instances() {
  local filter="${1:-}"
  INSTANCE_SERVICES=()
  INSTANCE_NAMES=()
  INSTANCE_TITLES=()
  INSTANCE_ICONS=()

  if [ ! -f "$INSTANCES_CONF" ]; then
    die "Não encontrei $INSTANCES_CONF"
  fi

  if [ -n "$filter" ]; then
    validate_service "$filter"
  fi

  local line service_and_name extras service name title icon seen key
  seen=""

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="$(trim "$line")"
    [ -z "$line" ] && continue
    case "$line" in
      \#*) continue ;;
    esac

    extras=""
    if [[ "$line" == *"|"* ]]; then
      service_and_name="${line%%|*}"
      extras="${line#*|}"
    else
      service_and_name="$line"
    fi
    service_and_name="$(trim "$service_and_name")"

    if [[ "$service_and_name" != *:* ]]; then
      die "Linha inválida em $INSTANCES_CONF: $line"$'\n'"Use: serviço:nome"
    fi

    service="${service_and_name%%:*}"
    name="${service_and_name#*:}"
    service="$(trim "$service")"
    name="$(trim "$name")"
    validate_service "$service"

    if [ -z "$name" ] || [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      die "Nome de instância inválido: '$name'"
    fi

    if [ -n "$filter" ] && [ "$service" != "$filter" ]; then
      continue
    fi

    key="$service:$name"
    case " $seen " in
      *" $key "*)
        echo "Ignorando duplicata em $INSTANCES_CONF: $key"
        continue
        ;;
    esac
    seen="$seen $key"

    title=""
    icon=""
    if [ -n "$extras" ]; then
      IFS='|' read -r title icon _ <<< "$extras"
      title="$(trim "$title")"
      icon="$(trim "$icon")"
    fi
    [ -z "$title" ] && title="$(default_title "$service" "$name")"
    [ -z "$icon" ] && icon="$(default_icon "$service" "$name")"

    INSTANCE_SERVICES+=("$service")
    INSTANCE_NAMES+=("$name")
    INSTANCE_TITLES+=("$title")
    INSTANCE_ICONS+=("$icon")
  done < "$INSTANCES_CONF"

  if [ "${#INSTANCE_NAMES[@]}" -eq 0 ]; then
    if [ -n "$filter" ]; then
      die "Nenhuma instância de '$filter' em $INSTANCES_CONF"
    fi
    die "Nenhuma instância em $INSTANCES_CONF"
  fi
}

names_for_service() {
  local want="$1" i
  for i in "${!INSTANCE_SERVICES[@]}"; do
    if [ "${INSTANCE_SERVICES[$i]}" = "$want" ]; then
      echo "${INSTANCE_NAMES[$i]}"
    fi
  done
}

resolve_linux_app_path() {
  local service="$1"
  local candidate
  case "$service" in
    claude)
      if [ -n "${CLAUDE_APP_PATH:-}" ]; then
        printf '%s' "$CLAUDE_APP_PATH"
        return 0
      fi
      for candidate in /usr/bin/claude "$HOME/.local/bin/claude" "$HOME/Applications/Claude"; do
        if [ -x "$candidate" ]; then
          printf '%s' "$candidate"
          return 0
        fi
      done
      if command -v claude >/dev/null 2>&1; then
        command -v claude
        return 0
      fi
      ;;
    cursor)
      if [ -n "${CURSOR_APP_PATH:-}" ]; then
        printf '%s' "$CURSOR_APP_PATH"
        return 0
      fi
      for candidate in /usr/bin/cursor /usr/share/cursor/cursor "$HOME/.local/bin/cursor"; do
        if [ -x "$candidate" ]; then
          printf '%s' "$candidate"
          return 0
        fi
      done
      if command -v cursor >/dev/null 2>&1; then
        command -v cursor
        return 0
      fi
      ;;
    *)
      die "Serviço desconhecido: $service"
      ;;
  esac
  return 1
}

parse_optional_service_arg() {
  local arg="${1:-}"
  if [ -z "$arg" ]; then
    printf ''
    return 0
  fi
  validate_service "$arg"
  printf '%s' "$arg"
}

launcher_name_from_filename() {
  local filename="$1" label="$2"
  local name
  name="${filename#"$label ("}"
  name="${name%.command}"
  name="${name%.desktop}"
  name="${name%.lnk}"
  name="${name%.app}"
  name="${name%)}"
  printf '%s' "$name"
}

prune_stale_launchers() {
  local desktop_dir="$1" label="$2"
  shift 2
  local keep_names=("$@")
  local launcher base name keep k

  [ -d "$desktop_dir" ] || return 0
  shopt -s nullglob
  for launcher in \
    "$desktop_dir/$label ("*.command \
    "$desktop_dir/$label ("*.desktop
  do
    base="$(basename "$launcher")"
    name="$(launcher_name_from_filename "$base" "$label")"
    keep=0
    for k in "${keep_names[@]}"; do
      if [ "$k" = "$name" ]; then
        keep=1
        break
      fi
    done
    if [ "$keep" -eq 0 ]; then
      rm -f "$launcher"
      echo "Removido (não está em instances.conf): $launcher"
    fi
  done
  shopt -u nullglob
}

prune_stale_raycast() {
  local scripts_dir="$1" service="$2"
  shift 2
  local keep_names=("$@")
  local script base name keep k

  [ -d "$scripts_dir" ] || return 0
  shopt -s nullglob
  for script in "$scripts_dir/$service-"*.sh; do
    base="$(basename "$script")"
    name="${base#"$service-"}"
    name="${name%.sh}"
    keep=0
    for k in "${keep_names[@]}"; do
      if [ "$k" = "$name" ]; then
        keep=1
        break
      fi
    done
    if [ "$keep" -eq 0 ]; then
      rm -f "$script"
      echo "Removido (não está em instances.conf): $script"
    fi
  done
  shopt -u nullglob
}

. "$_LIB_DIR/import.sh"

prompt_and_remove_instances() {
  local count all_n skip_n i ans chosen idx service name dest path any_exist skip key k
  local selected_keys=() skip_keys=() lock_dirs=()

  if [ ! -t 0 ]; then
    die "Remoção interativa precisa de um terminal."
  fi

  load_instances
  count=${#INSTANCE_NAMES[@]}
  all_n=$((count + 1))
  skip_n=$((count + 2))

  echo ""
  echo "Quais instâncias apagar? (lista de $INSTANCES_CONF)"
  i=0
  while [ "$i" -lt "$count" ]; do
    service="${INSTANCE_SERVICES[$i]}"
    name="${INSTANCE_NAMES[$i]}"
    dest="$(service_instances_base "$service")/$name"
    if [ -e "$dest" ]; then
      echo "  $((i + 1))) $service:$name"
      echo "      $dest"
    else
      echo "  $((i + 1))) $service:$name  (pasta ainda não existe)"
    fi
    i=$((i + 1))
  done
  echo "  $all_n) Todas as acima"
  echo "  $skip_n) Cancelar"
  echo "Várias: 1,3"

  while true; do
    ans="$(ask "Escolha [$skip_n]: ")"
    chosen="$(parse_numbered_pick "$ans" "$count")" || continue
    break
  done

  if [ -z "$chosen" ]; then
    echo "Cancelado."
    return 0
  fi

  if [ "$chosen" = "__ALL__" ]; then
    i=0
    while [ "$i" -lt "$count" ]; do
      selected_keys+=("${INSTANCE_SERVICES[$i]}:${INSTANCE_NAMES[$i]}")
      i=$((i + 1))
    done
  else
    while IFS= read -r idx; do
      [ -n "$idx" ] || continue
      selected_keys+=("${INSTANCE_SERVICES[$idx]}:${INSTANCE_NAMES[$idx]}")
    done <<EOF
$chosen
EOF
  fi

  i=0
  while [ "$i" -lt "$count" ]; do
    key="${INSTANCE_SERVICES[$i]}:${INSTANCE_NAMES[$i]}"
    skip=0
    for k in "${selected_keys[@]}"; do
      if [ "$k" = "$key" ]; then
        skip=1
        break
      fi
    done
    if [ "$skip" -eq 0 ]; then
      skip_keys+=("$key")
    fi
    i=$((i + 1))
  done

  echo ""
  echo "Vai APAGAR (não dá para desfazer):"
  for key in "${selected_keys[@]}"; do
    service="${key%%:*}"
    name="${key#*:}"
    echo "  $key"
    echo "    linha em $INSTANCES_CONF"
    any_exist=0
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if [ -e "$path" ] || [ -L "$path" ]; then
        echo "    $path"
        any_exist=1
      fi
    done < <(each_instance_artifact "$service" "$name")
    if [ "$any_exist" -eq 0 ]; then
      echo "    (nada no disco além da linha do conf)"
    fi
  done
  echo ""
  echo "Ficam intactos:"
  if [ "${#skip_keys[@]}" -gt 0 ]; then
    for key in "${skip_keys[@]}"; do
      echo "  $key"
    done
  else
    echo "  (nenhuma outra instância do conf)"
  fi
  echo "  perfil padrão do Dock / app original"
  echo "  pasta compartilhada de scripts do Raycast"
  echo ""

  ans="$(ask "Digite apagar para confirmar: ")"
  case "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" in
    apagar) ;;
    *)
      echo "Cancelado."
      return 0
      ;;
  esac

  lock_dirs=()
  for key in "${selected_keys[@]}"; do
    service="${key%%:*}"
    name="${key#*:}"
    dest="$(service_instances_base "$service")/$name"
    lock_dirs+=("$dest")
  done
  if ! ensure_profiles_unlocked "${lock_dirs[@]}"; then
    echo "Cancelado."
    return 0
  fi

  for key in "${selected_keys[@]}"; do
    service="${key%%:*}"
    name="${key#*:}"
    remove_instance "$service" "$name"
  done
  remove_keys_from_instances_conf "${selected_keys[@]}"
  echo ""
  echo "Pronto. As instâncias escolhidas saíram do disco e de $INSTANCES_CONF."
}
