#!/usr/bin/env bash
set -euo pipefail
SECONDS=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Source logging utilities
source "$PROJECT_ROOT/common/utils.sh"

log_info "Creating metadata files from domains.yml + ports.yml"

# Check for yq
if ! command -v yq >/dev/null 2>&1; then
  log_error "yq is required but not found"
  log_info "Install with: brew install yq (macOS) or apt-get install yq (Linux)"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  log_error "python3 is required for metadata generation"
  exit 1
fi

mkdir -p config-registry/state/metadata-cache

# Acquire lightweight lock to avoid concurrent runs
LOCK_FILE="config-registry/state/.lock"
LOCK_DIR="${LOCK_FILE}.dir"

if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE" || exit 1
  if ! flock -n 9; then
    log_warn "Metadata generation already running"
    exit 0
  fi
  trap 'flock -u 9 2>/dev/null || true' EXIT
else
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log_warn "Metadata generation already running"
    exit 0
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
fi

# Calculate source hash for drift detection
# Hash both files together for composite fingerprint
SOURCE_HASH=$(sha256sum config-registry/env/domains.yml config-registry/env/ports.yml 2>/dev/null | sha256sum | cut -d' ' -f1)
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Read domains from domains.yml
DOMAINS=$(yq '.domains[].name' config-registry/env/domains.yml)

for domain in $DOMAINS; do
  tmp=$(mktemp)
  cache_file="config-registry/state/metadata-cache/${domain}.yml"

  # Get dependencies for this domain
  DEPS=$(yq -o=json ".domains[] | select(.name == \"$domain\") | .dependencies // []" config-registry/env/domains.yml)

  # Get ports for this domain from ports.yml
  HAS_PORTS=$(yq -e ".$domain" config-registry/env/ports.yml >/dev/null 2>&1 && echo "yes" || echo "no")

  TEMPLATE_HASH=$(python3 - <<PY
from pathlib import Path
import hashlib
base = Path('domains/${domain}/templates')
paths = sorted(base.rglob('*.tmpl')) if base.exists() else []
if paths:
    h = hashlib.sha256()
    for path in paths:
        h.update(path.read_bytes())
    print(h.hexdigest())
PY
  )
  TEMPLATE_HASH=${TEMPLATE_HASH//$'\n'/}

  # Generate metadata.yml by combining domain definition + port assignments
  {
    cat <<YAML
_meta:
  generated_at: ${GENERATED_AT}
  git_commit: ${GIT_COMMIT}
  source_hash: ${SOURCE_HASH}
YAML
    if [[ -n "$TEMPLATE_HASH" ]]; then
      printf '  template_hash: %s\n' "$TEMPLATE_HASH"
    fi
    printf '  domain: %s\n\n' "$domain"
    printf 'name: %s\n\n' "$domain"

    printf 'dependencies:\n'
    if [[ "$DEPS" != "[]" && -n "$DEPS" ]]; then
      echo "$DEPS" | yq -o=yaml '.[]' | sed 's/^/  - /'
    fi
    printf '\n'

    if [[ "$HAS_PORTS" == "yes" ]]; then
      printf 'ports:\n'
      yq -o=yaml ".$domain" config-registry/env/ports.yml | sed 's/^/  /'
      printf '\n'
    fi

    printf 'networks:\n  - %s-network\n' "$domain"
  } > "$tmp"

  # Only update if content changed (preserves file mtime if unchanged)
  if ! cmp -s "$tmp" "$cache_file" 2>/dev/null; then
    mv "$tmp" "$cache_file"
    log_success "Updated $cache_file"
  else
    rm "$tmp"
    log_debug "No changes to $cache_file"
  fi
done

for cached in config-registry/state/metadata-cache/*.yml; do
  [[ -f "$cached" ]] || continue
  domain=$(basename "${cached%.yml}")
  if ! echo "$DOMAINS" | grep -qx "$domain"; then
    log_warn "Removing stale cache: $cached"
    rm -f "$cached"
  fi
done

log_success "Metadata cache generated in config-registry/state/metadata-cache/ (took ${SECONDS}s)"
log_info "Review diffs: make diff-metadata"
log_info "Commit: make commit-metadata"
