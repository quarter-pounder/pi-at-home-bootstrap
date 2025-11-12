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

mkdir -p "${BACKUP_TMP}"

if docker ps --format '{{.Names}}' | grep -q '^forgejo-postgres$'; then
  docker exec forgejo-postgres pg_dump -U postgres forgejo >"${BACKUP_TMP}/forgejo.sql"
  docker exec forgejo-postgres pg_dump -U postgres woodpecker >"${BACKUP_TMP}/woodpecker.sql"
fi

if [[ ! -f "${RESTIC_PASSWORD_FILE}" ]]; then
  echo "Restic password file not found: ${RESTIC_PASSWORD_FILE}" >&2
  exit 1
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

rm -f "${BACKUP_TMP}/forgejo.sql" "${BACKUP_TMP}/woodpecker.sql"
