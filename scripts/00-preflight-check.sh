#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

echo "Running pre-flight checks..."
echo ""

ERRORS=0

check_os() {
  if [[ ! -f /etc/os-release ]]; then
    echo "${RED}✗${RESET} Cannot detect OS"
    ((ERRORS++))
    return
  fi

  source /etc/os-release
  if [[ "$ID" == "ubuntu" ]]; then
    echo "${GREEN}✓${RESET} OS: Ubuntu $VERSION_ID"
  else
    echo "${YELLOW}WARNING${RESET} OS: $ID $VERSION_ID (Ubuntu recommended)"
  fi
}

check_arch() {
  ARCH=$(uname -m)
  if [[ "$ARCH" == "aarch64" ]]; then
    echo "${GREEN}✓${RESET} Architecture: ARM64"
  else
    echo "${RED}✗${RESET} Architecture: $ARCH (ARM64 required)"
    ((ERRORS++))
  fi
}

check_memory() {
  MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
  if (( MEM_GB >= 4 )); then
    echo "${GREEN}✓${RESET} Memory: ${MEM_GB}GB"
  elif (( MEM_GB >= 2 )); then
    echo "${YELLOW}WARNING${RESET} Memory: ${MEM_GB}GB (4GB+ recommended)"
  else
    echo "${RED}✗${RESET} Memory: ${MEM_GB}GB (insufficient)"
    ((ERRORS++))
  fi
}

check_disk() {
  DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
  if (( DISK_GB >= 50 )); then
    echo "${GREEN}✓${RESET} Disk space: ${DISK_GB}GB available"
  elif (( DISK_GB >= 20 )); then
    echo "${YELLOW}WARNING${RESET} Disk space: ${DISK_GB}GB (50GB+ recommended)"
  else
    echo "${RED}✗${RESET} Disk space: ${DISK_GB}GB (insufficient)"
    ((ERRORS++))
  fi
}

check_internet() {
  if curl -s --max-time 5 https://github.com >/dev/null 2>&1; then
    echo "${GREEN}✓${RESET} Internet connection"
  else
    echo "${RED}✗${RESET} No internet connection"
    ((ERRORS++))
  fi
}

check_env() {
  if [[ -f .env ]]; then
    echo "${GREEN}✓${RESET} .env file exists"

    source .env
    REQUIRED_VARS=(HOSTNAME DOMAIN USERNAME EMAIL SSH_PUBLIC_KEY GITLAB_ROOT_PASSWORD GRAFANA_ADMIN_PASSWORD)
    MISSING=()

    for var in "${REQUIRED_VARS[@]}"; do
      if [[ -z "${!var:-}" ]]; then
        MISSING+=("$var")
      fi
    done

    if (( ${#MISSING[@]} > 0 )); then
      echo "${RED}✗${RESET} Missing required variables: ${MISSING[*]}"
      ((ERRORS++))
    else
      echo "${GREEN}✓${RESET} All required .env variables set"
    fi
  else
    echo "${RED}✗${RESET} .env file not found"
    ((ERRORS++))
  fi
}

check_sudo() {
  if sudo -n true 2>/dev/null; then
    echo "${GREEN}✓${RESET} Sudo access (passwordless)"
  elif sudo -v 2>/dev/null; then
    echo "${GREEN}✓${RESET} Sudo access (with password)"
  else
    echo "${RED}✗${RESET} No sudo access"
    ((ERRORS++))
  fi
}

check_os
check_arch
check_memory
check_disk
check_internet
check_env
check_sudo

echo ""
if (( ERRORS == 0 )); then
  echo "${GREEN}✓ All checks passed!${RESET} Ready to proceed."
  exit 0
else
  echo "${RED}✗ $ERRORS error(s) found.${RESET} Fix issues before continuing."
  exit 1
fi

