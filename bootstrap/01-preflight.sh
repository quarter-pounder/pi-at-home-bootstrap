#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

source "$(dirname "$0")/utils.sh"

   if [[ $EUID -ne 0 ]]; then
     log_error "Run with sudo: sudo bootstrap/01-preflight.sh"
     exit 1
   fi

log_info "Running pre-flight checks..."
echo ""

ERRORS=0
WARNINGS=0

# Local helpers that wrap logging functions without clashing with utils.sh
pass_msg() { log_success "$@"; }
warn_msg() { log_warn "$@"; ((WARNINGS++)); }
fail_msg() { log_error "$@"; ((ERRORS++)); }

bytes_free() { df -B1 "${1:-.}" | awk 'NR==2{print $4}'; }

# OS / arch / resources
check_os() {
  if [[ ! -f /etc/os-release ]]; then fail_msg "Cannot detect OS"; return; fi
  source /etc/os-release
  if [[ "${ID:-}" == "ubuntu" ]]; then
    pass_msg "OS: Ubuntu ${VERSION_ID:-unknown}"
  else
    warn_msg "OS: ${ID:-unknown} ${VERSION_ID:-} (Ubuntu recommended)"
  fi
}

check_arch() {
  local a; a=$(uname -m)
  if [[ "$a" == "aarch64" ]]; then pass_msg "Architecture: ARM64"; else fail_msg "Architecture: $a (ARM64 required)"; fi
}

check_memory() {
  local mem_mb; mem_mb=$(free -m | awk '/^Mem:/{print $2}')
  local mem_gb; mem_gb=$(awk "BEGIN {printf \"%.1f\", $mem_mb/1024}")
  if (( mem_mb >= 4096 )); then
    pass_msg "Memory: ${mem_gb}GB"
  elif (( mem_mb >= 2048 )); then
    warn_msg "Memory: ${mem_gb}GB (4GB+ recommended)"
  else
    fail_msg "Memory: ${mem_gb}GB (insufficient)"
  fi
}

check_disk() {
  local free_b; free_b=$(bytes_free .)
  if (( free_b >= 100000000000 )); then pass_msg "Disk space: $((free_b/1024/1024/1024))GB available";
  elif (( free_b >= 20000000000 )); then warn_msg "Disk space: $((free_b/1024/1024/1024))GB (50GB+ recommended)";
  else fail_msg "Disk space: $((free_b/1024/1024/1024))GB (insufficient)"; fi
}

# Connectivity
check_internet() {
  if curl -fsSL --max-time 5 --retry 2 https://github.com >/dev/null 2>&1 && \
     curl -fsSL --max-time 5 --retry 2 https://get.docker.com >/dev/null 2>&1; then
    pass_msg "Internet connectivity"
  else
    fail_msg "No reliable internet connectivity"
  fi
}

# Environment validation
check_env() {
  if [[ -f config-registry/env/base.env ]]; then
    pass_msg "Base environment file exists"
    set -a
    source config-registry/env/base.env
    set +a

    local required=(HOSTNAME USERNAME TIMEZONE DOMAIN)
    local missing=()
    for v in "${required[@]}"; do
      [[ -n "${!v:-}" ]] || missing+=("$v")
    done
    if (( ${#missing[@]} )); then
      warn_msg "Base env missing values: ${missing[*]} (set them in config-registry/env/base.env before deploying)"
    else
      pass_msg "Core variables present"
    fi
  else
    warn_msg "Base environment file not found (normal during bootstrap)"
  fi
}

# Sudo
check_sudo() {
  if sudo -n true 2>/dev/null; then pass_msg "Sudo access (passwordless)"
  elif sudo -v 2>/dev/null; then pass_msg "Sudo access (with password)"
  else fail_msg "No sudo access"; fi
}

# Hardware
check_pi_model() {
  local model="unknown"
  [[ -f /proc/device-tree/model ]] && model=$(tr -d '\0' </proc/device-tree/model || true)
  log_info "Detected model: $model"
  if [[ "$model" != *"Raspberry Pi"* ]]; then warn_msg "Non-Raspberry Pi environment detected"; fi
}

# Run checks
check_os
check_arch
check_memory
check_disk
check_internet
check_sudo
check_pi_model

check_env

# Summary section
echo ""
log_info "=== Preflight Summary ==="
if (( ERRORS == 0 )); then
  log_success "Result: PASS"
  if (( WARNINGS > 0 )); then
    log_warn "Warnings: $WARNINGS"
  else
    log_info "Warnings: 0"
  fi
  log_info "Errors: 0"
  log_info "Status: Ready to proceed"
else
  log_error "Result: FAIL"
  log_error "Errors: $ERRORS"
  if (( WARNINGS > 0 )); then
    log_warn "Warnings: $WARNINGS"
  else
    log_info "Warnings: 0"
  fi
  log_info "Status: Fix issues before continuing"
fi
echo ""

# Exit with appropriate code
if (( ERRORS == 0 )); then
  exit 0
else
  exit 1
fi
