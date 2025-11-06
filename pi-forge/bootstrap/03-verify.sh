#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source "$(dirname "$0")/utils.sh"

echo "[i] Verifying installation..."

ERRORS=0
WARNINGS=0

# Helpers
ok()   { echo "${GREEN}OK${RESET} $*"; }
warn() { echo "${YELLOW}WARNING${RESET} $*"; ((WARNINGS++)); }
bad()  { echo "${RED}FAIL${RESET} $*"; ((ERRORS++)); }

# Docker installation
check_docker_installed() {
  if command -v docker >/dev/null 2>&1; then
    ok "Docker installed"
    docker_version=$(docker --version)
    echo "  Version: $docker_version"
  else
    bad "Docker not found"
  fi
}

# Docker Compose
check_docker_compose() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "Docker Compose available"
    compose_version=$(docker compose version)
    echo "  Version: $compose_version"
  else
    bad "Docker Compose not available"
  fi
}

# Docker daemon status
check_docker_daemon() {
  if sudo systemctl is-active --quiet docker; then
    ok "Docker daemon running (systemctl)"
  else
    bad "Docker daemon not running (systemctl)"
  fi
}

# Docker group membership
check_docker_group() {
  if groups | grep -q docker; then
    ok "User in docker group"
  else
    warn "User not in docker group (logout/login required)"
  fi
}

# Docker functionality test
check_docker_functionality() {
  if docker run --rm hello-world >/dev/null 2>&1; then
    ok "Docker functionality test passed"
  else
    bad "Docker functionality test failed"
  fi
}

# Required tools
check_tools() {
  for tool in curl wget git jq yq envsubst ansible-vault; do
    if command -v "$tool" >/dev/null 2>&1; then
      ok "Tool: $tool"
    else
      bad "Missing tool: $tool"
    fi
  done
}

# /srv directory and mount
check_srv_directory() {
  if [[ -d /srv ]]; then
    ok "/srv directory exists"

    if mountpoint -q /srv 2>/dev/null; then
      ok "/srv is a mount point"

      # Check if mounted on NVMe
      SRV_DEVICE=$(df /srv | awk 'NR==2 {print $1}')
      if [[ -n "$SRV_DEVICE" ]]; then
        if echo "$SRV_DEVICE" | grep -q "nvme"; then
          ok "/srv mounted on NVMe device: $SRV_DEVICE"
        else
          warn "/srv mounted on $SRV_DEVICE (NVMe recommended for performance)"
        fi
      fi
    else
      warn "/srv is not a mount point (consider mounting dedicated partition)"
    fi
  else
    warn "/srv directory missing (will be created as needed)"
  fi
}

# Disk space check
check_disk_space() {
  if [[ -d /srv ]] && mountpoint -q /srv 2>/dev/null; then
    local free_b; free_b=$(df -B1 /srv | awk 'NR==2{print $4}')
    local free_gb=$((free_b / 1024 / 1024 / 1024))
    if (( free_gb >= 50 )); then
      ok "Disk space on /srv: ${free_gb}GB available"
    elif (( free_gb >= 20 )); then
      warn "Disk space on /srv: ${free_gb}GB (50GB+ recommended)"
    else
      bad "Disk space on /srv: ${free_gb}GB (insufficient)"
    fi
  fi
}

# Memory and swap
check_memory() {
  local mem_gb; mem_gb=$(free -g | awk '/^Mem:/{print $2}')
  if (( mem_gb >= 4 )); then
    ok "Memory: ${mem_gb}GB"
  elif (( mem_gb >= 2 )); then
    warn "Memory: ${mem_gb}GB (4GB+ recommended)"
  else
    bad "Memory: ${mem_gb}GB (insufficient)"
  fi

  local swap_gb; swap_gb=$(free -g | awk '/^Swap:/{print $2}')
  if (( swap_gb > 0 )); then
    ok "Swap: ${swap_gb}GB"
  else
    warn "No swap configured (consider adding swap for stability)"
  fi
}

# Docker info validation
check_docker_info() {
  if docker info >/dev/null 2>&1; then
    ok "Docker info accessible"

    local storage_driver; storage_driver=$(docker info 2>/dev/null | grep -i "storage driver" | awk '{print $3}' || echo "unknown")
    if [[ "$storage_driver" == "overlay2" ]]; then
      ok "Docker storage driver: overlay2"
    else
      warn "Docker storage driver: $storage_driver (overlay2 recommended)"
    fi
  else
    bad "Cannot access Docker info"
  fi
}

# Network interfaces
check_network() {
  if ip link show | grep -q "state UP"; then
    local up_interfaces; up_interfaces=$(ip link show | grep "state UP" | wc -l)
    ok "Network interfaces up: $up_interfaces"
  else
    warn "No network interfaces detected as UP"
  fi
}

# Optional disk throughput test
test_disk_throughput() {
  if [[ ! -d /srv ]] || ! mountpoint -q /srv 2>/dev/null; then
    return 0
  fi

  echo "[i] Running disk throughput test (this may take a moment)..."
  local test_file="/srv/.bootstrap_throughput_test"
  local test_size=100

  if dd if=/dev/zero of="$test_file" bs=1M count="$test_size" conv=fdatasync 2>&1 | tail -1 >/dev/null; then
    rm -f "$test_file"
    ok "Disk write test completed"
  else
    warn "Disk write test failed or skipped"
    rm -f "$test_file"
  fi
}

# Run all checks
check_docker_installed
check_docker_compose
check_docker_daemon
check_docker_group
check_docker_functionality
check_docker_info
check_tools
check_srv_directory
check_disk_space
check_memory
check_network

# Optional throughput test (can be skipped for faster verification)
if [[ "${SKIP_THROUGHPUT_TEST:-}" != "1" ]]; then
  test_disk_throughput
fi

echo ""
if (( ERRORS == 0 )); then
  log_success "Verification complete. All checks passed."
  if (( WARNINGS > 0 )); then
    echo "${YELLOW}Note:${RESET} $WARNINGS warning(s) reported."
  fi
  exit 0
else
  log_error "Verification failed. $ERRORS error(s) found."
  if (( WARNINGS > 0 )); then
    echo "${YELLOW}Also:${RESET} $WARNINGS warning(s) reported."
  fi
  exit 1
fi
