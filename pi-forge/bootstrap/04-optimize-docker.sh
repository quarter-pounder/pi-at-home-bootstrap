#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source bootstrap/utils.sh
trap 'log_error "Docker optimization interrupted"; exit 1' INT TERM

log_info "Optimizing Docker daemon for Raspberry Pi..."

require_root

DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
BACKUP_JSON="${DOCKER_DAEMON_JSON}.bak.$(date +%Y%m%d_%H%M%S)"

mkdir -p /etc/docker

if [[ -f "$DOCKER_DAEMON_JSON" ]]; then
  log_info "Backing up existing Docker config"
  cp "$DOCKER_DAEMON_JSON" "$BACKUP_JSON"
  log_success "Backup saved to $BACKUP_JSON"
fi

log_info "Applying Pi-optimized Docker configuration"

tee "$DOCKER_DAEMON_JSON" > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-address-pools": [
    {
      "base": "172.80.0.0/16",
      "size": 24
    }
  ],
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
EOF

log_success "Docker configuration written"

# Validate JSON integrity
if ! jq empty "$DOCKER_DAEMON_JSON" >/dev/null 2>&1; then
  log_error "Malformed daemon.json — please check syntax"
  exit 1
fi

if systemctl is-active --quiet docker; then
  log_info "Restarting Docker daemon to apply configuration..."
  systemctl restart docker

  log_info "Waiting for Docker to become ready..."
  for i in {1..30}; do
    if docker ps >/dev/null 2>&1; then
      log_success "Docker is up and running"
      break
    fi
    sleep 1
  done

  if ! docker ps >/dev/null 2>&1; then
    log_warn "Docker daemon may not be fully ready (check manually)"
  fi
else
  log_warn "Docker not running, configuration will apply on next boot/start"
fi

STORAGE_DRIVER=$(docker info 2>/dev/null | awk -F': ' '/Storage Driver/{print $2}')
if [[ "$STORAGE_DRIVER" == "overlay2" ]]; then
  log_success "Storage driver: overlay2"
else
  log_warn "Storage driver is $STORAGE_DRIVER (expected overlay2)"
fi

log_success "Docker optimization complete"

# Check if user is in docker group
ACTUAL_USER="${SUDO_USER:-${USER:-root}}"
if [[ "$ACTUAL_USER" != "root" ]]; then
  if ! groups "$ACTUAL_USER" | grep -q docker; then
    log_warn "User '$ACTUAL_USER' is not in docker group — re-login required"
  fi
fi
