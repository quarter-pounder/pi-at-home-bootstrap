#!/usr/bin/env bash
set -Eeuo pipefail
trap 'log_error "Installation interrupted"; exit 1' INT TERM
cd "$(dirname "$0")/.."

source "$(dirname "$0")/utils.sh"

# Verify sudo access
if ! sudo -n true 2>/dev/null && ! sudo -v 2>/dev/null; then
  log_error "This script requires sudo access. Please ensure you have sudo privileges."
  exit 1
fi

log_info "Installing core dependencies..."

sudo apt-get update -qq

# Core tools
sudo apt-get install -y \
  curl \
  wget \
  git \
  jq \
  python3 \
  python3-pip \
  python3-jinja2 \
  python3-yaml \
  gettext-base \
  ansible \
  rsync \
  htop \
  vim \
  unzip \
  ca-certificates \
  gnupg \
  lsb-release \
  software-properties-common \
  qemu-user-static \
  fail2ban \
  unattended-upgrades

# Raspberry Pi specific tools
sudo apt-get install -y \
  rpi-eeprom \
  nvme-cli \
  util-linux \
  dosfstools \
  e2fsprogs \
  parted \
  pv

if command -v yq >/dev/null 2>&1; then
  log_info "Removing Python yq package (switching to Go binary build)"
  sudo apt-get remove -y yq || log_warn "Unable to remove apt yq (continuing)"
fi

if command -v snap >/dev/null 2>&1; then
  log_info "Installing yq via snap (Go build)"
  sudo snap install yq >/dev/null
else
  log_warn "snap not available; falling back to upstream yq binary download"
  YQ_BIN=/usr/local/bin/yq
  sudo curl -sSL \
    "https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_arm64" \
    -o "$YQ_BIN"
  sudo chmod +x "$YQ_BIN"
fi

if ! yq --version 2>/dev/null | grep -qi "mikefarah"; then
  log_error "yq installation failed (expected mikefarah/yq build)"
  exit 1
fi

log_success "Core dependencies installed successfully"
