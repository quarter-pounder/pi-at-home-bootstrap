#!/usr/bin/env bash
set -euo pipefail

# Color helpers (TTY-safe)
if [[ -t 1 ]]; then
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

log_debug()   { [[ "${DEBUG:-0}" == "1" ]] && echo "${BLUE}[$(timestamp)] [DEBUG]${RESET} $*" >&2 || true; }
log_info()    { echo "${BLUE}[$(timestamp)] [INFO]${RESET} $*"; }
log_warn()    { echo "${YELLOW}[$(timestamp)] [WARN]${RESET} $*"; }
log_error()   { echo "${RED}[$(timestamp)] [ERROR]${RESET} $*" >&2; }
log_success() { echo "${GREEN}[$(timestamp)] [OK]${RESET} $*"; }

# Environment loader (optional, for post-bootstrap use)
load_env() {
  if [[ -f config-registry/env/base.env ]]; then
    set -a
    source config-registry/env/base.env
    set +a
  else
    log_warn "Base environment file not found at config-registry/env/base.env"
    log_info "This is normal during bootstrap phase. Config registry will be set up later."
    return 0
  fi
}

# Safety helpers
require_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This action requires root privileges. Try sudo."
    exit 1
  fi
}

confirm_continue() {
  read -p "Continue? (yes/no): " -r
  if [[ ! $REPLY =~ ^yes$ ]]; then
    log_warn "User cancelled."
    exit 0
  fi
}

trap_cleanup() {
  log_warn "Script interrupted. Cleaning up..."
  exit 1
}

trap trap_cleanup INT TERM
