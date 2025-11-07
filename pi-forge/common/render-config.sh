#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Source logging utilities
source "$PROJECT_ROOT/common/utils.sh"
source "$PROJECT_ROOT/common/lib/env.sh"

DOMAIN="$1"
ENVIRONMENT="${2:-dev}"

log_info "Rendering $DOMAIN for environment $ENVIRONMENT"

SRC="domains/${DOMAIN}/templates"
DST="generated/${DOMAIN}"
mkdir -p "$DST"

# Load environment (layered: base → override → secrets)
set -a
source config-registry/env/base.env
[ -f "config-registry/env/overrides/${ENVIRONMENT}.env" ] && source "config-registry/env/overrides/${ENVIRONMENT}.env"

# Decrypt and source secrets
if [ -f config-registry/env/secrets.env.vault ]; then
  if [ ! -f .vault_pass ]; then
    log_error ".vault_pass file not found"
    exit 1
  fi
  TMP_SECRETS=$(mktemp)
  trap 'rm -f "$TMP_SECRETS" 2>/dev/null || true' EXIT
  log_debug "Decrypting secrets.env.vault"
  if ! ansible-vault decrypt --vault-password-file .vault_pass \
    config-registry/env/secrets.env.vault --output "$TMP_SECRETS"; then
    rm -f "$TMP_SECRETS"
    log_error "Vault decryption failed"
    exit 1
  fi
  source "$TMP_SECRETS"
fi
set +a

# Load ports.yml as PORT_* variables
# ports.yml structure: {domain: {port_name: number}}
# Converts to: PORT_{DOMAIN}_{PORT_NAME} (uppercase)
# Example: gitlab.http: 80 → PORT_GITLAB_HTTP=80
export_ports

# Check if templates directory exists
if [ ! -d "$SRC" ]; then
  log_warn "Template directory $SRC does not exist"
  log_info "Complete (no templates to render)"
  exit 0
fi

# Render templates (templates use $PORT_* vars)
rendered=0
for f in "$SRC"/*.tmpl; do
  [ -f "$f" ] || continue
  if [[ "${DRYRUN:-0}" == "1" ]]; then
    log_info "DRYRUN=1 skipping render for $(basename "$f")"
    continue
  fi
  out="$DST/$(basename "${f%.tmpl}")"
  safe_envsubst < "$f" > "$out"
  log_debug "Rendered $out"
  rendered=$((rendered+1))
done

if (( rendered == 0 )); then
  log_warn "No templates matched (*.tmpl) in $SRC"
fi

log_success "[Render] Render complete"
