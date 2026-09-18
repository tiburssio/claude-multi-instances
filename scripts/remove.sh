#!/bin/bash
# Remove launchers e dados isolados. Não mexe no app nem no perfil original.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

usage() {
  echo "Uso: $0 [serviço:nome ...] [claude|cursor|all] [--yes]"
  echo ""
  echo "Sem argumentos: lista as contas de instances.conf e pede confirmação."
  echo "Com serviço:nome: apaga só essas instâncias (dados + atalhos + linha do conf)."
  echo "claude|cursor|all: todas as contas desse app que estão no conf."
  echo "O app original e o perfil padrão permanecem. Pastas que não estão no conf"
  echo "não são apagadas."
  exit 1
}

YES=""
TARGETS=()
SERVICES=()

for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    -h|--help) usage ;;
    claude|cursor)
      SERVICES+=("$arg")
      ;;
    all)
      SERVICES+=(claude cursor)
      ;;
    *:*)
      service="${arg%%:*}"
      name="${arg#*:}"
      validate_service "$service"
      if [ -z "$name" ] || [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
        die "Nome de instância inválido: '$name'"
      fi
      TARGETS+=("$arg")
      ;;
    *) usage ;;
  esac
done

if [ "${#TARGETS[@]}" -eq 0 ] && [ "${#SERVICES[@]}" -eq 0 ]; then
  prompt_and_remove_instances
  exit 0
fi

load_instances

if [ "${#SERVICES[@]}" -gt 0 ]; then
  i=0
  while [ "$i" -lt "${#INSTANCE_NAMES[@]}" ]; do
    service="${INSTANCE_SERVICES[$i]}"
    name="${INSTANCE_NAMES[$i]}"
    for svc in "${SERVICES[@]}"; do
      if [ "$service" = "$svc" ]; then
        TARGETS+=("$service:$name")
      fi
    done
    i=$((i + 1))
  done
fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
  die "Nenhuma instância correspondente em $INSTANCES_CONF"
fi

# Dedupe
UNIQUE=()
for key in "${TARGETS[@]}"; do
  already=0
  for u in "${UNIQUE[@]}"; do
    if [ "$u" = "$key" ]; then
      already=1
      break
    fi
  done
  if [ "$already" -eq 0 ]; then
    UNIQUE+=("$key")
  fi
done
TARGETS=("${UNIQUE[@]}")

for key in "${TARGETS[@]}"; do
  service="${key%%:*}"
  name="${key#*:}"
  i=0
  found=0
  while [ "$i" -lt "${#INSTANCE_NAMES[@]}" ]; do
    if [ "${INSTANCE_SERVICES[$i]}" = "$service" ] && [ "${INSTANCE_NAMES[$i]}" = "$name" ]; then
      found=1
      break
    fi
    i=$((i + 1))
  done
  if [ "$found" -eq 0 ]; then
    die "Não achei $key em $INSTANCES_CONF"
  fi
done

echo "Vai APAGAR (não dá para desfazer):"
for key in "${TARGETS[@]}"; do
  service="${key%%:*}"
  name="${key#*:}"
  echo "  $key"
  echo "    linha em $INSTANCES_CONF"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -e "$path" ] || [ -L "$path" ]; then
      echo "    $path"
    fi
  done < <(each_instance_artifact "$service" "$name")
done
echo ""
echo "NÃO será removido:"
echo "  - Os apps originais e o perfil padrão"
echo "  - Instâncias que não foram escolhidas"
echo "  - Pastas isoladas que não estão no instances.conf"
echo ""

if [ "$YES" != "1" ]; then
  ans="$(ask "Digite apagar para confirmar: ")"
  case "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" in
    apagar) ;;
    *)
      echo "Cancelado."
      exit 0
      ;;
  esac
fi

lock_dirs=()
for key in "${TARGETS[@]}"; do
  service="${key%%:*}"
  name="${key#*:}"
  lock_dirs+=("$(service_instances_base "$service")/$name")
done
if ! ensure_profiles_unlocked "${lock_dirs[@]}"; then
  echo "Cancelado."
  exit 0
fi

for key in "${TARGETS[@]}"; do
  service="${key%%:*}"
  name="${key#*:}"
  remove_instance "$service" "$name"
done
remove_keys_from_instances_conf "${TARGETS[@]}"

echo ""
echo "Pronto. As instâncias escolhidas saíram do disco e de $INSTANCES_CONF."
