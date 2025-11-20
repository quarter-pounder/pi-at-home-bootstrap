#!/usr/bin/env bash
# Minimal utilities for bootstrap scripts (self-contained, no external dependencies)

if [[ ! -t 1 ]]; then
  RED=""; GREEN=""; YELLOW=""; RESET=""
else
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
fi

log()   { printf '%s [INFO] %s\n' "$(date '+%F %T')" "$*"; }
warn()  { printf '%s%s [WARN] %s%s\n' "$YELLOW" "$(date '+%F %T')" "$*" "$RESET"; }
error() { printf '%s%s [ERROR] %s%s\n' "$RED" "$(date '+%F %T')" "$*" "$RESET" >&2; }
ok()    { printf '%s%s [OK] %s%s\n' "$GREEN" "$(date '+%F %T')" "$*" "$RESET"; }
debug() { [[ "${DEBUG:-0}" == "1" ]] && printf '%s [DEBUG] %s\n' "$(date '+%F %T')" "$*" >&2 || true; }

# Alias for compatibility with common/utils.sh naming
log_info()    { log "$@"; }
log_warn()    { warn "$@"; }
log_error()   { error "$@"; }
log_success() { ok "$@"; }
log_debug()   { debug "$@"; }

# Safety helpers
require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This action requires root privileges. Try sudo."
    exit 1
  fi
}

confirm_continue() {
  local prompt="${1:-Continue? (yes/no): }"
  read -p "$prompt" -r
  [[ $REPLY =~ ^yes$ ]] || { warn "User cancelled."; exit 0; }
}

# Load environment variables in the correct order (matching render_config.py)
# Order: base.env -> .env -> secrets.env.vault (if available)
load_env_layers() {
  local root_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

  # Load base.env
  if [[ -f "${root_dir}/config-registry/env/base.env" ]]; then
    debug "Loading ${root_dir}/config-registry/env/base.env"
    set -a
    source "${root_dir}/config-registry/env/base.env"
    set +a
  fi

  # Load .env (overrides base.env)
  if [[ -f "${root_dir}/.env" ]]; then
    debug "Loading ${root_dir}/.env"
    set -a
    source "${root_dir}/.env"
    set +a
  fi

  # Try to load secrets.env.vault if ansible-vault is available
  local vault_file="${root_dir}/config-registry/env/secrets.env.vault"
  local pass_file="${root_dir}/.vault_pass"
  if [[ -f "${vault_file}" ]] && command -v ansible-vault >/dev/null 2>&1 && [[ -f "${pass_file}" ]]; then
    if [[ "${VAULT_SKIP_DECRYPT:-0}" != "1" ]]; then
      debug "Decrypting and loading ${vault_file}"
      local decrypted
      if decrypted=$(ansible-vault view "${vault_file}" --vault-password-file "${pass_file}" 2>/dev/null); then
        set -a
        eval "$(echo "${decrypted}" | grep -v '^#' | grep -v '^$' | sed 's/^/export /')"
        set +a
      else
        warn "Failed to decrypt secrets.env.vault (skipping)"
      fi
    else
      debug "Skipping vault decryption (VAULT_SKIP_DECRYPT=1)"
    fi
  fi
}
