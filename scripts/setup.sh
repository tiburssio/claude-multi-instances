#!/bin/bash
# Entrada única: detecta o SO e pergunta o que configurar.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

OS="$(detect_os)"
SKIP_IMPORT=1
SETUP_QUIET=1
export SKIP_IMPORT SETUP_QUIET

prepare_dirs_only() {
  local filter="${1:-}"
  local i service name
  load_instances "$filter"
  for i in "${!INSTANCE_NAMES[@]}"; do
    service="${INSTANCE_SERVICES[$i]}"
    name="${INSTANCE_NAMES[$i]}"
    case "$OS" in
      macos)
        if ! macos_service_ready "$service"; then
          if [ "$service" = "codex" ]; then
            echo "codex não encontrado no PATH ($service:$name)" >&2
          else
            echo "App não encontrado: $(service_macos_app_path "$service") ($service)" >&2
            continue
          fi
        fi
        ;;
    esac
    prepare_instance_dir "$service" "$(service_instances_base "$service")/$name"
  done
}

run_filtered() {
  local script="$1"
  local filter="$2"
  if [ -n "$filter" ]; then
    "$script" "$filter" >/dev/null
  else
    "$script" >/dev/null
  fi
}

run_windows_ps() {
  local extra="$1"
  local ps
  ps="$(command -v powershell.exe || command -v pwsh || true)"
  if [ -z "$ps" ]; then
    die "Não achei PowerShell. Rode .\\setup.ps1 neste PC."
  fi
  SKIP_IMPORT=1 "$ps" -ExecutionPolicy Bypass -File "$ROOT/scripts/windows/setup-launchers.ps1" $extra
}

services_arg() {
  case "$1" in
    claude|cursor|codex) echo "$1" ;;
    *) echo "" ;;
  esac
}

choose_filter() {
  echo "Quais apps nesta rodada?"
  echo "  1) Claude  (app Desktop)"
  echo "  2) Cursor  (IDE)"
  echo "  3) Codex   (CLI no Terminal)"
  echo "  4) Todos"
  case "$(ask "Escolha: ")" in
    1) CHOSEN_FILTER="claude" ;;
    2) CHOSEN_FILTER="cursor" ;;
    3) CHOSEN_FILTER="codex" ;;
    4) CHOSEN_FILTER="" ;;
    *)
      echo "Opção inválida."
      return 1
      ;;
  esac
}

configure_codex() {
  cleanup_our_desktop_launchers "claude cursor"
  prepare_dirs_only codex
  prune_codex_shims
  ensure_codex_user_bin_on_path
  unset SKIP_IMPORT
  load_instances codex
  prompt_and_import_for_services codex
  print_codex_terminal_commands
}

configure_gui() {
  local gui_services="$1"
  local launchers svc
  [ -n "$gui_services" ] || return 0

  case "$OS" in
    macos)
      echo "Como você quer abrir as instâncias isoladas?"
      echo "  1) Raycast"
      echo "  2) Spotlight"
      echo "  3) Raycast e Spotlight"
      echo "  4) Área de Trabalho"
      echo "  5) Só pastas, sem atalho"
      case "$(ask "Escolha: ")" in
        1) launchers="raycast" ;;
        2) launchers="spotlight" ;;
        3) launchers="raycast spotlight" ;;
        4) launchers="desktop" ;;
        5) launchers="none" ;;
        *)
          echo "Opção inválida."
          return 1
          ;;
      esac
      ;;
    linux)
      echo "Onde criar os atalhos das instâncias isoladas?"
      echo "  1) Menu de aplicativos"
      echo "  2) Área de Trabalho"
      echo "  3) Só pastas, sem atalho"
      case "$(ask "Escolha [1]: ")" in
        ""|1) launchers="linux-apps" ;;
        2) launchers="linux-desktop" ;;
        3) launchers="none" ;;
        *)
          echo "Opção inválida."
          return 1
          ;;
      esac
      ;;
    windows)
      echo "Onde criar os atalhos das instâncias isoladas?"
      echo "  1) Menu Iniciar"
      echo "  2) Área de Trabalho"
      echo "  3) Só pastas, sem atalho"
      case "$(ask "Escolha [1]: ")" in
        ""|1) launchers="win-start" ;;
        2) launchers="win-desktop" ;;
        3) launchers="none" ;;
        *)
          echo "Opção inválida."
          return 1
          ;;
      esac
      ;;
    *)
      die "SO não suportado: $(uname -s)"
      ;;
  esac

  for svc in $gui_services; do
    [ -n "$(list_conf_keys "$svc")" ] || continue
    case "$launchers" in
      *raycast*) run_filtered "$ROOT/scripts/macos/setup-raycast.sh" "$svc" ;;
    esac
    case "$launchers" in
      *spotlight*) run_filtered "$ROOT/scripts/macos/setup-spotlight.sh" "$svc" ;;
    esac
    case "$launchers" in
      desktop) run_filtered "$ROOT/scripts/macos/setup-desktop.sh" "$svc" ;;
      linux-apps)
        LAUNCHER_DIR="$HOME/.local/share/applications" \
          run_filtered "$ROOT/scripts/linux/setup-launchers.sh" "$svc"
        ;;
      linux-desktop)
        LAUNCHER_DIR="$HOME/Desktop" \
          run_filtered "$ROOT/scripts/linux/setup-launchers.sh" "$svc"
        ;;
      win-start)
        LAUNCHER_DIR="${APPDATA:-$HOME/AppData/Roaming}/Microsoft/Windows/Start Menu/Programs" \
          run_windows_ps "-Service $svc"
        ;;
      win-desktop)
        LAUNCHER_DIR="${USERPROFILE:-$HOME}/Desktop" \
          run_windows_ps "-Service $svc"
        ;;
      none) prepare_dirs_only "$svc" ;;
    esac
  done

  case "$launchers" in
    desktop|linux-desktop|win-desktop)
      cleanup_our_desktop_launchers "$gui_services"
      ;;
    *)
      cleanup_our_desktop_launchers
      ;;
  esac
}

configure() {
  local script_filter
  choose_filter || return 0
  prompt_and_add_instances "$CHOSEN_FILTER"
  script_filter="$(services_arg "$CHOSEN_FILTER")"
  if [ -z "$(list_conf_keys "$script_filter")" ]; then
    echo "Não há contas deste app na lista. Acrescente uma no passo anterior ou edite $INSTANCES_CONF."
    return 0
  fi

  if [ "$CHOSEN_FILTER" = "codex" ]; then
    configure_codex
    return 0
  fi

  case "$CHOSEN_FILTER" in
    claude)
      configure_gui claude || return 0
      ;;
    cursor)
      configure_gui cursor || return 0
      ;;
    *)
      configure_gui "claude cursor" || return 0
      if [ -n "$(list_conf_keys codex)" ]; then
        prepare_dirs_only codex
        prune_codex_shims
        ensure_codex_user_bin_on_path
      fi
      ;;
  esac

  unset SKIP_IMPORT
  load_instances "$script_filter"
  if [ -n "$script_filter" ]; then
    prompt_and_import_for_services "$script_filter"
  else
    prompt_and_import_for_services "$(all_services)"
  fi

  if [ -z "$CHOSEN_FILTER" ]; then
    print_codex_terminal_commands
  fi
}

do_remove_all() {
  prompt_and_remove_instances
}

echo "O que você quer fazer?"
echo "  1) Configurar Nova Instancia  (recomendado, pastas e logins que já existem não são apagados)"
echo "  2) Apagar Instância (exige confirmação)"
echo "  3) Sair"

case "$(ask "Escolha [1]: ")" in
  ""|1) configure ;;
  2) do_remove_all ;;
  3|q|Q) exit 0 ;;
  *) die "Opção inválida." ;;
esac
