#!/bin/bash
# Importa o perfil padrão do Claude/Cursor/Codex para instâncias isoladas.
#
# Uso:
#   ./scripts/import.sh
#   ./scripts/import.sh claude
#   ./scripts/import.sh cursor
#   ./scripts/import.sh codex
#   SKIP_IMPORT=1 ./scripts/macos/setup-desktop.sh   # setup sem perguntar

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

FILTER="$(parse_optional_service_arg "${1:-}")"
load_instances "$FILTER"

services=""
for i in "${!INSTANCE_SERVICES[@]}"; do
  services="$(list_add "$services" "${INSTANCE_SERVICES[$i]}")"
done

prompt_and_import_for_services "$services"
