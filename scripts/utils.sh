#!/usr/bin/env bash
set -euo pipefail

load_env() {
  if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
  else
    echo "[!] .env file not found"
    exit 1
  fi
}

detect_latest_lts() {
  if [[ -z "${UBUNTU_VERSION:-}" ]]; then
    UBUNTU_VERSION=$(curl -s https://api.launchpad.net/devel/ubuntu/series |
      grep -oP '"name": "\K[0-9]{2}\.[0-9]{2}(?=")' | sort -V | tail -1)
  fi
}

confirm_device() {
  if [[ -z "${NVME_DEVICE:-}" ]]; then
    NVME_DEVICE=$(lsblk -dno NAME,TYPE | grep disk | grep nvme | awk '{print "/dev/"$1}' | head -1)
  fi
  echo "[i] Target device: ${NVME_DEVICE}"
}
