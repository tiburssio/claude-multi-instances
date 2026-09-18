#!/bin/bash
# Entrada única: detecta o SO e pergunta o que configurar.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

OS="$(detect_os)"
SKIP_IMPORT=1
export SKIP_IMPORT

prepare_dirs_only() {
  local filter="${1:-}"
  local i service name app_path
  load_instances "$filter"
  for i in "${!INSTANCE_NAMES[@]}"; do
    service="${INSTANCE_SERVICES[$i]}"
    name="${INSTANCE_NAMES[$i]}"
    case "$OS" in
      macos)
        app_path="$(service_macos_app_path "$service")"
        if [ ! -d "$app_path" ]; then
          echo "App não encontrado: $app_path ($service)"
          continue
        fi
        ;;
    esac
    prepare_instance_dir "$service" "$(service_instances_base "$service")/$name"
    echo "Pasta pronta: $service:$name"
  done
}

run_filtered() {
  local script="$1"
  local filter="$2"
  if [ -n "$filter" ]; then
    "$script" "$filter"
  else
    "$script"
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
    claude|cursor) echo "$1" ;;
    *) echo "" ;;
  esac
}

choose_filter() {
  echo ""
  echo "Quais apps configurar?"
  echo "  1) Claude"
  echo "  2) Cursor"
  echo "  3) Ambos"
  case "$(ask "Escolha: ")" in
    1) CHOSEN_FILTER="claude" ;;
    2) CHOSEN_FILTER="cursor" ;;
    3) CHOSEN_FILTER="" ;;
    *)
      echo "Opção inválida."
      return 1
      ;;
  esac
}

clean_desktop_if_wanted() {
  local filter="$1"
  local service path any=0
  local services="claude cursor"

  [ -n "$filter" ] && services="$filter"

  echo ""
  echo "Atalhos na Área de Trabalho (não são obrigatórios se você usa Raycast ou Spotlight):"
  for service in $services; do
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      echo "  $path"
      any=1
    done < <(each_desktop_launcher "$service")
  done
  if [ "$any" -eq 0 ]; then
    return 0
  fi
  case "$(ask "Remover esses arquivos? [Y/n] ")" in
    ""|y|Y|s|S|sim|Sim) ;;
    *) return 0 ;;
  esac
  for service in $services; do
    remove_desktop_launchers_for_service "$service"
  done
}

configure() {
  local launchers script_filter
  choose_filter || return 0
  prompt_and_add_instances "$CHOSEN_FILTER"
  script_filter="$(services_arg "$CHOSEN_FILTER")"
  if [ -z "$(list_conf_keys "$script_filter")" ]; then
    echo "Nenhuma instância no conf para configurar. Use a opção 2 ou edite $INSTANCES_CONF."
    return 0
  fi

  echo ""
  case "$OS" in
    macos)
      echo "Como você abre os apps?"
      echo "  1) Raycast (Script Commands)"
      echo "  2) Spotlight (mini-apps em ~/Applications; Cmd+Espaço)"
      echo "  3) Raycast e Spotlight"
      echo "  4) Arquivos na Área de Trabalho"
      echo "  5) Só as pastas de dados, sem atalhos"
      case "$(ask "Escolha: ")" in
        1) launchers="raycast" ;;
        2) launchers="spotlight" ;;
        3) launchers="raycast spotlight" ;;
        4) launchers="desktop" ;;
        5) launchers="none" ;;
        *)
          echo "Opção inválida."
          return 0
          ;;
      esac
      ;;
    linux)
      echo "Onde criar os atalhos?"
      echo "  1) Menu de aplicativos (~/.local/share/applications)"
      echo "  2) Área de Trabalho"
      echo "  3) Só as pastas de dados, sem atalhos"
      case "$(ask "Escolha [1]: ")" in
        ""|1) launchers="linux-apps" ;;
        2) launchers="linux-desktop" ;;
        3) launchers="none" ;;
        *)
          echo "Opção inválida."
          return 0
          ;;
      esac
      ;;
    windows)
      echo "Onde criar os atalhos?"
      echo "  1) Menu Iniciar"
      echo "  2) Área de Trabalho"
      echo "  3) Só as pastas de dados, sem atalhos"
      case "$(ask "Escolha [1]: ")" in
        ""|1) launchers="win-start" ;;
        2) launchers="win-desktop" ;;
        3) launchers="none" ;;
        *)
          echo "Opção inválida."
          return 0
          ;;
      esac
      ;;
    *)
      die "SO não suportado: $(uname -s)"
      ;;
  esac

  echo ""
  case "$launchers" in
    *raycast*) run_filtered "$ROOT/scripts/macos/setup-raycast.sh" "$script_filter" ;;
  esac
  case "$launchers" in
    *spotlight*) run_filtered "$ROOT/scripts/macos/setup-spotlight.sh" "$script_filter" ;;
  esac
  case "$launchers" in
    desktop) run_filtered "$ROOT/scripts/macos/setup-desktop.sh" "$script_filter" ;;
    linux-apps)
      LAUNCHER_DIR="$HOME/.local/share/applications" \
        run_filtered "$ROOT/scripts/linux/setup-launchers.sh" "$script_filter"
      ;;
    linux-desktop)
      LAUNCHER_DIR="$HOME/Desktop" \
        run_filtered "$ROOT/scripts/linux/setup-launchers.sh" "$script_filter"
      ;;
    win-start)
      LAUNCHER_DIR="${APPDATA:-$HOME/AppData/Roaming}/Microsoft/Windows/Start Menu/Programs" \
        run_windows_ps "$( [ -n "$script_filter" ] && echo "-Service $script_filter" )"
      ;;
    win-desktop)
      LAUNCHER_DIR="${USERPROFILE:-$HOME}/Desktop" \
        run_windows_ps "$( [ -n "$script_filter" ] && echo "-Service $script_filter" )"
      ;;
    none) prepare_dirs_only "$script_filter" ;;
  esac

  case "$launchers" in
    desktop|linux-desktop|win-desktop) ;;
    *) clean_desktop_if_wanted "$script_filter" ;;
  esac

  echo ""
  echo "Setup aditivo: pastas já existentes em ~/.claude-instances e ~/.cursor-instances não foram apagadas."

  unset SKIP_IMPORT
  load_instances "$script_filter"
  if [ -n "$script_filter" ]; then
    prompt_and_import_for_services "$script_filter"
  else
    prompt_and_import_for_services "claude cursor"
  fi
}

do_import() {
  choose_filter || return 0
  unset SKIP_IMPORT
  load_instances "$(services_arg "$CHOSEN_FILTER")"
  if [ -n "$CHOSEN_FILTER" ]; then
    prompt_and_import_for_services "$CHOSEN_FILTER"
  else
    prompt_and_import_for_services "claude cursor"
  fi
}

do_remove_desktop() {
  echo ""
  remove_desktop_launchers_for_service claude
  remove_desktop_launchers_for_service cursor
  echo "Atalhos da Área de Trabalho removidos. Dados isolados continuam intactos."
}

do_add() {
  prompt_and_add_instances
  case "$(ask "Configurar atalhos agora? [Y/n] ")" in
    n|N|nao|não)
      echo "Opção 1 cria os atalhos a partir do conf."
      ;;
    *) configure ;;
  esac
}

do_remove_all() {
  prompt_and_remove_instances
}

echo "claude-multi-instances  ($(detect_os))"
echo "Lista de contas: $INSTANCES_CONF"
echo ""
echo "O que você quer fazer?"
echo "  1) Configurar instâncias"
echo "  2) Adicionar instância"
echo "  3) Importar dados do perfil padrão"
echo "  4) Remover atalhos da Área de Trabalho (mantém os dados)"
echo "  5) Apagar instâncias isoladas (irreversível: dados + atalhos)"
echo "  6) Sair"

case "$(ask "Escolha [1]: ")" in
  ""|1) configure ;;
  2) do_add ;;
  3) do_import ;;
  4) do_remove_desktop ;;
  5) do_remove_all ;;
  6|q|Q) exit 0 ;;
  *) die "Opção inválida." ;;
esac
