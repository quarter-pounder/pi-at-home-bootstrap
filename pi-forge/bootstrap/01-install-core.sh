#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source bootstrap/utils.sh

echo "[i] Installing core dependencies..."

# Update package lists
sudo apt update

# Install essential packages
sudo apt install -y \
  curl \
  wget \
  git \
  jq \
  yq \
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

# Install additional tools for Pi
sudo apt install -y \
  rpi-eeprom \
  nvme-cli \
  util-linux \
  dosfstools \
  e2fsprogs \
  parted \
  pv

echo "[i] Core dependencies installed successfully"
