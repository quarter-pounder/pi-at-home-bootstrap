#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

export_ports() {
  local yaml="${ROOT_DIR}/config-registry/env/ports.yml"
  if [[ ! -f "$yaml" ]]; then
    if command -v log_error >/dev/null 2>&1; then
      log_error "ports.yml not found at $yaml"
    else
      printf '[ERROR] ports.yml not found at %s\n' "$yaml" >&2
    fi
    return 1
  fi
  eval "$(
    yq -o=shell "$yaml" |
    awk -F'=' '{
      gsub(/^ports_/, "", $1);
      printf "PORT_%s=%s\n", toupper($1), $2
    }'
  )"
}

safe_envsubst() {
  if ! command -v envsubst >/dev/null 2>&1; then
    if command -v log_error >/dev/null 2>&1; then
      log_error "envsubst not found. Install gettext-base."
    else
      printf '[ERROR] envsubst not found. Install gettext-base.\n' >&2
    fi
    exit 1
  fi
  envsubst "$@"
}
