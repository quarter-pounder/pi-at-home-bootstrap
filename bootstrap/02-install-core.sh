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
  yq \
  python3 \
  python3-pip \
  gettext-base \
  ansible \
  rsync \
  htop \
  vim \
  unzip \
  ca-certificates \
  gnupg \
  lsb-release \
  software-properties-common

# Raspberry Pi specific tools
sudo apt-get install -y \
  rpi-eeprom \
  nvme-cli \
  util-linux \
  dosfstools \
  e2fsprogs \
  parted \
  pv

log_success "Core dependencies installed successfully"
