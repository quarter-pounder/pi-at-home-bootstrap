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

# Alias for compatibility with common/utils.sh naming
log_info()    { log "$@"; }
log_warn()    { warn "$@"; }
log_error()   { error "$@"; }
log_success() { ok "$@"; }

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
