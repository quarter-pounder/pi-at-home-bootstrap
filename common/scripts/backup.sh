#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
BACKUP_TMP="/srv/backups/tmp"
RESTIC_PASSWORD_FILE="${ROOT}/config-registry/env/restic.password"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/srv/backups/local}"

if ! command -v restic >/dev/null 2>&1; then
  echo "restic not installed – install restic before running this script" >&2
  exit 1
fi

mkdir -p "${RESTIC_REPOSITORY}" "${BACKUP_TMP}"

tmp_files=()
cleanup() {
  for f in "${tmp_files[@]}"; do
    rm -f "$f"
  done
}
trap cleanup EXIT

tmp_dump() {
  local name=$1
  tmp_files+=("${BACKUP_TMP}/${name}.sql")
  docker exec forgejo-postgres pg_dump -U postgres "$name" >"${BACKUP_TMP}/${name}.sql"
}

if docker ps --format '{{.Names}}' | grep -q '^forgejo-postgres$'; then
  tmp_dump forgejo
  tmp_dump woodpecker
fi

if [[ ! -f "${RESTIC_PASSWORD_FILE}" ]]; then
  echo "Restic password file not found: ${RESTIC_PASSWORD_FILE}" >&2
  exit 1
fi

if ! restic -r "${RESTIC_REPOSITORY}" snapshots >/dev/null 2>&1; then
  echo "Initializing restic repository at ${RESTIC_REPOSITORY}"
  restic -r "${RESTIC_REPOSITORY}" init
fi

export RESTIC_PASSWORD_FILE
restic -r "${RESTIC_REPOSITORY}" backup \
  /srv/forgejo/data \
  /srv/woodpecker/server \
  /srv/adblocker \
  /srv/registry \
  /srv/monitoring/prometheus \
  /srv/monitoring/alertmanager \
  /srv/monitoring/grafana \
  "${BACKUP_TMP}/forgejo.sql" \
  "${BACKUP_TMP}/woodpecker.sql" \
  "${ROOT}/config-registry/env/secrets.env.vault"

restic -r "${RESTIC_REPOSITORY}" forget --prune \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6
