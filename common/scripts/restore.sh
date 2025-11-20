#!/usr/bin/env bash
set -euo pipefail

# --- Usage -------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <restic-snapshot-id|latest> [dest-dir]" >&2
  echo "Example: $0 latest /srv/restore-test" >&2
  exit 1
fi

SNAPSHOT_ID="$1"
DEST="${2:-/srv/restores/${SNAPSHOT_ID}}"

# --- Prerequisites ------------------------------------------------------------
for cmd in restic mkdir rsync; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "[ERR] Missing dependency: $cmd" >&2
    exit 1
  }
done

[[ -n "${RESTIC_REPOSITORY:-}" ]] || {
  echo "[ERR] RESTIC_REPOSITORY environment variable is required" >&2
  exit 1
}
[[ -n "${RESTIC_PASSWORD_FILE:-}" ]] || {
  echo "[ERR] RESTIC_PASSWORD_FILE environment variable is required" >&2
  exit 1
}

# --- Preparation --------------------------------------------------------------
mkdir -p "$DEST"
DEST="$(realpath "$DEST")"

echo "[Restore] Target directory: $DEST"
echo "[Restore] Snapshot: $SNAPSHOT_ID"
echo "[Restore] Repository: $RESTIC_REPOSITORY"

# --- Snapshot validation ------------------------------------------------------
if ! restic -r "$RESTIC_REPOSITORY" snapshots --compact | grep -q "$SNAPSHOT_ID"; then
  if [[ "$SNAPSHOT_ID" != "latest" ]]; then
    echo "[WARN] Snapshot $SNAPSHOT_ID not found in repository" >&2
    echo "Use 'restic snapshots' to list available IDs." >&2
    exit 1
  fi
fi

# --- Actual restore -----------------------------------------------------------
TMP_RESTORE="$(mktemp -d "${DEST}.partial.XXXX")"
trap 'rm -rf "$TMP_RESTORE"' EXIT

echo "[Restore] Restoring to temporary path: $TMP_RESTORE"
restic -r "$RESTIC_REPOSITORY" restore "$SNAPSHOT_ID" --target "$TMP_RESTORE"

# --- Finalize -----------------------------------------------------------------
echo "[Restore] Moving restored data into $DEST"
rsync -aHAX --info=progress2 "$TMP_RESTORE"/ "$DEST"/

echo "[OK] Restore complete → $DEST"

