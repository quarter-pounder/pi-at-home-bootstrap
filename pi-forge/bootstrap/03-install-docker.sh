#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source "$(dirname "$0")/utils.sh"
trap 'log_error "Docker installation interrupted"; exit 1' INT TERM

log_info "Installing Docker Engine and Compose..."

# Verify sudo access
if ! sudo -n true 2>/dev/null && ! sudo -v 2>/dev/null; then
  log_error "This script requires sudo access. Please ensure sudo privileges."
  exit 1
fi

log_info "Fetching and installing Docker Engine (official script)..."
curl -fsSL https://get.docker.com | sudo sh

# Disable autostart if systemd spun it up automatically
if sudo systemctl is-active --quiet docker; then
  log_info "Stopping auto-started Docker daemon (will be optimized later)"
  sudo systemctl stop docker
fi

# Enable but don’t start
sudo systemctl enable docker.service containerd.service

# Add user to docker group
sudo usermod -aG docker "${USERNAME:-$USER}"

# Verify installation
if command -v docker >/dev/null 2>&1; then
  log_success "Docker installed: $(docker --version)"
else
  log_error "Docker binary not found after installation"
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  log_success "Docker Compose plugin detected"
else
  log_warn "Docker Compose plugin not found (may require manual install)"
fi

# Confirm optimization stage expectation
if [[ ! -f /etc/docker/daemon.json ]]; then
  log_info "Daemon config not present yet — will be created by 04-optimize-docker.sh"
fi

log_success "Docker installation complete"
log_info "Log out and back in for Docker group changes to take effect"
