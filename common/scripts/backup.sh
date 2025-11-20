#!/usr/bin/env bash
set -euo pipefail

log()   { printf '%s [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn()  { printf '%s [WARN] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
error() { printf '%s [ERR ] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# --- Privilege escalation ----------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/srv/backups/local}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-${ROOT}/config-registry/env/restic.password}"
BACKUP_TMP="${BACKUP_TMP:-/srv/backups/tmp}"

if [[ $EUID -ne 0 ]]; then
  exec sudo RESTIC_REPOSITORY="$RESTIC_REPOSITORY" RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE" bash "$0" "$@"
fi

# --- Paths -------------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# --- Prerequisites -----------------------------------------------------------
PG_DUMP_TIMEOUT="${PG_DUMP_TIMEOUT:-300}"

for cmd in restic docker timeout; do
  command -v "$cmd" >/dev/null 2>&1 || {
    error "Missing dependency: $cmd"
    exit 1
  }
done

[[ -f "$RESTIC_PASSWORD_FILE" ]] || {
  error "Restic password file not found: $RESTIC_PASSWORD_FILE"
  exit 1
}

mkdir -p "$RESTIC_REPOSITORY" "$BACKUP_TMP"

# --- Cleanup handling --------------------------------------------------------
tmp_files=()
cleanup() {
  for f in "${tmp_files[@]:-}"; do
    [[ -f "$f" ]] && rm -f "$f"
  done
}
trap cleanup EXIT
trap 'error "Backup interrupted"; exit 130' INT TERM

# --- Database dump helper ----------------------------------------------------
dump_db() {
  local container=$1
  local dbname=$2
  local outfile="${BACKUP_TMP}/${dbname}-${TIMESTAMP}.sql"
  tmp_files+=("$outfile")

  log "[Dump] ${dbname} from ${container} → ${outfile} (timeout: ${PG_DUMP_TIMEOUT}s)"

  local pg_user="${POSTGRES_SUPERUSER:-postgres}"
  local pg_password="${POSTGRES_SUPERUSER_PASSWORD:-}"
  local exec_cmd=(docker exec -i)
  if [[ -n "$pg_password" ]]; then
    exec_cmd+=(-e "PGPASSWORD=$pg_password")
  fi

  if ! timeout "$PG_DUMP_TIMEOUT" "${exec_cmd[@]}" "$container" pg_dump -U "$pg_user" "$dbname" >"$outfile"; then
    rc=$?
    if [[ $rc -eq 124 ]]; then
      error "[Dump] ${dbname} timed out after ${PG_DUMP_TIMEOUT}s"
    else
      error "[Dump] ${dbname} failed with exit code $rc"
    fi
    exit $rc
  fi
}

# --- PostgreSQL dumps (if container present) ---------------------------------
if docker ps --format '{{.Names}}' | grep -q '^forgejo-postgres$'; then
  dump_db forgejo-postgres forgejo
else
  warn "forgejo-postgres container not found — skipping DB dumps"
fi

# --- Initialize repository if missing ---------------------------------------
export RESTIC_PASSWORD_FILE RESTIC_REPOSITORY

if ! restic -r "$RESTIC_REPOSITORY" snapshots >/dev/null 2>&1; then
  log "[Init] Initializing restic repository at $RESTIC_REPOSITORY"
  restic -r "$RESTIC_REPOSITORY" init
fi

# --- Run backup --------------------------------------------------------------
log "[Backup] Starting restic backup to $RESTIC_REPOSITORY"

BACKUP_MODE="${BACKUP_MODE:-manual}"
BACKUP_PRUNE="${BACKUP_PRUNE:-0}"
BACKUP_DATE="${BACKUP_DATE:-$(date +%Y%m%d)}"
BACKUP_HOST="${BACKUP_HOST:-$(hostname)}"

FULL_PATHS=(
  /srv/forgejo/data
  /srv/forgejo-actions-runner
  /srv/adblocker
  /srv/registry
  /srv/monitoring/prometheus
  /srv/monitoring/alertmanager
  /srv/monitoring/grafana
)

CLOUD_PATHS=(
  /srv/forgejo/data
)

if [[ "$BACKUP_MODE" == "cloud" ]]; then
  BACKUP_PATHS=("${CLOUD_PATHS[@]}")
else
  BACKUP_PATHS=("${FULL_PATHS[@]}")
fi

BACKUP_PATHS+=("${tmp_files[@]-}")
BACKUP_PATHS+=("${ROOT}/config-registry/env/secrets.env.vault")

restic -r "$RESTIC_REPOSITORY" backup \
  --tag "$BACKUP_DATE" \
  --tag "$BACKUP_MODE" \
  --hostname "$BACKUP_HOST" \
  --verbose \
  "${BACKUP_PATHS[@]}"

backup_status=$?

if [[ $backup_status -ne 0 ]]; then
  error "Restic backup failed (exit code $backup_status); skipping prune"
  exit $backup_status
fi

if [[ "$BACKUP_PRUNE" -eq 1 ]]; then
  log "[Cleanup] Pruning old backups"
  restic -r "$RESTIC_REPOSITORY" forget --prune \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6
else
  log "[Cleanup] Skipping prune run (BACKUP_PRUNE=$BACKUP_PRUNE)"
fi

log "[Done] Backup complete."
