#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <restic-snapshot-id> [dest-dir]" >&2
  exit 1
fi

SNAPSHOT="$1"
DEST="${2:-/srv/restores/${SNAPSHOT}}"

mkdir -p "${DEST}"

if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
  echo "RESTIC_REPOSITORY environment variable is required" >&2
  exit 1
fi

if [[ -z "${RESTIC_PASSWORD_FILE:-}" ]]; then
  echo "RESTIC_PASSWORD_FILE environment variable is required" >&2
  exit 1
fi

restic restore "${SNAPSHOT}" --target "${DEST}"

echo "Restore complete. Files are in ${DEST}"
