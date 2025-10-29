#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Color helpers (TTY-safe)
if [[ -t 1 ]]; then
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

echo "Running pre-flight checks..."
echo ""

ERRORS=0
WARNINGS=0

# Helpers
ok()   { echo "${GREEN}OK${RESET} $*"; }
warn() { echo "${YELLOW}WARNING${RESET} $*"; ((WARNINGS++)); }
bad()  { echo "${RED}FAIL${RESET} $*"; ((ERRORS++)); }

need_cmd() {
  local c=$1; local pkg=${2:-$1}
  if command -v "$c" >/dev/null 2>&1; then ok "Command: $c"; else bad "Missing command: $c (install: $pkg)"; fi
}

bytes_free() { df -B1 "${1:-.}" | awk 'NR==2{print $4}'; }

# OS / arch / resources
check_os() {
  if [[ ! -f /etc/os-release ]]; then bad "Cannot detect OS"; return; fi
  source /etc/os-release
  if [[ "${ID:-}" == "ubuntu" ]]; then
    ok "OS: Ubuntu ${VERSION_ID:-unknown}"
  else
    warn "OS: ${ID:-unknown} ${VERSION_ID:-} (Ubuntu recommended)"
  fi
}

check_arch() {
  local a; a=$(uname -m)
  if [[ "$a" == "aarch64" ]]; then ok "Architecture: ARM64"; else bad "Architecture: $a (ARM64 required)"; fi
}

check_memory() {
  local mem_gb; mem_gb=$(free -g | awk '/^Mem:/{print $2}')
  if (( mem_gb >= 4 )); then ok "Memory: ${mem_gb}GB"; elif (( mem_gb >= 2 )); then warn "Memory: ${mem_gb}GB (4GB+ recommended)"; else bad "Memory: ${mem_gb}GB (insufficient)"; fi
}

check_disk() {
  local free_b; free_b=$(bytes_free .)
  if (( free_b >= 100000000000 )); then ok "Disk space: $((free_b/1024/1024/1024))GB available";
  elif (( free_b >= 20000000000 )); then warn "Disk space: $((free_b/1024/1024/1024))GB (50GB+ recommended)";
  else bad "Disk space: $((free_b/1024/1024/1024))GB (insufficient)"; fi
}

# Connectivity / tools
check_internet() {
  if curl -fsSL --max-time 5 https://github.com >/dev/null 2>&1 && \
     curl -fsSL --max-time 5 https://get.docker.com >/dev/null 2>&1; then
    ok "Internet connectivity"
  else
    bad "No reliable internet connectivity"
  fi
}

check_tools() {
  need_cmd curl curl
  need_cmd wget wget
  need_cmd envsubst gettext-base
  need_cmd jq jq
  need_cmd yq yq
  need_cmd ansible-vault ansible
}

# Environment validation
check_env() {
  if [[ -f config-registry/env/base.env ]]; then
    ok "Base environment file exists"
    source config-registry/env/base.env

    local required=(HOSTNAME USERNAME TIMEZONE DOMAIN)
    local missing=()
    for v in "${required[@]}"; do
      [[ -n "${!v:-}" ]] || missing+=("$v")
    done
    if (( ${#missing[@]} )); then bad "Missing required variables: ${missing[*]}"; else ok "Core variables present"; fi
  else
    bad "Base environment file not found"
    return
  fi
}

# Sudo
check_sudo() {
  if sudo -n true 2>/dev/null; then ok "Sudo access (passwordless)"
  elif sudo -v 2>/dev/null; then ok "Sudo access (with password)"
  else bad "No sudo access"; fi
}

# Hardware
check_pi_model() {
  local model="unknown"
  [[ -f /proc/device-tree/model ]] && model=$(tr -d '\0' </proc/device-tree/model || true)
  echo "Detected model: ${BLUE}${model}${RESET}"
  if [[ "$model" != *"Raspberry Pi"* ]]; then warn "Non-Raspberry Pi environment detected"; fi
}

# Run checks
check_os
check_arch
check_memory
check_disk
check_internet
check_tools
check_sudo
check_pi_model

# Load env if present
if [[ -f config-registry/env/base.env ]]; then source config-registry/env/base.env; fi
check_env

echo ""
if (( ERRORS == 0 )); then
  echo "${GREEN}All checks passed.${RESET} Ready to proceed."
  if (( WARNINGS > 0 )); then
    echo "${YELLOW}Note:${RESET} $WARNINGS warning(s) reported."
  fi
  exit 0
else
  echo "${RED}$ERRORS error(s) found.${RESET} Fix issues before continuing."
  if (( WARNINGS > 0 )); then
    echo "${YELLOW}Also:${RESET} $WARNINGS warning(s) reported."
  fi
  exit 1
fi
