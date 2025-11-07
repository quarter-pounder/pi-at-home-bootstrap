#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
#  Color and logging helpers
# ──────────────────────────────────────────────
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

log_info()    { echo "${BLUE}[$(timestamp)] [INFO]${RESET} $*"; }
log_warn()    { echo "${YELLOW}[$(timestamp)] [WARN]${RESET} $*"; }
log_error()   { echo "${RED}[$(timestamp)] [ERROR]${RESET} $*" >&2; }
log_success() { echo "${GREEN}[$(timestamp)] [OK]${RESET} $*"; }

# ──────────────────────────────────────────────
#  Environment loader
# ──────────────────────────────────────────────
load_env() {
  if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
  else
    log_error ".env file not found. Copy env.example → .env and configure it."
    exit 1
  fi
}

# ──────────────────────────────────────────────
#  Ubuntu LTS detection (fallback if unset)
# ──────────────────────────────────────────────
detect_latest_lts() {
  if [[ -z "${UBUNTU_VERSION:-}" ]]; then
    UBUNTU_VERSION=$(
      curl -s https://api.launchpad.net/devel/ubuntu/series \
        | grep -oP '"name": "\K[0-9]{2}\.[0-9]{2}(?=")' \
        | sort -V | tail -1
    )
    log_info "Detected latest Ubuntu LTS: ${UBUNTU_VERSION}"
  fi
}

# ──────────────────────────────────────────────
#  NVMe device auto-detection
# ──────────────────────────────────────────────
confirm_device() {
  if [[ -z "${NVME_DEVICE:-}" ]]; then
    NVME_DEVICE=$(lsblk -dno NAME,TYPE | grep disk | grep nvme | awk '{print "/dev/"$1}' | head -1)
  fi
  if [[ -z "${NVME_DEVICE}" ]]; then
    log_error "No NVMe device detected. Check connection."
    exit 1
  fi
  log_info "Target device: ${NVME_DEVICE}"
}

# ──────────────────────────────────────────────
#  Safety and convenience helpers
# ──────────────────────────────────────────────
require_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This action requires root privileges. Try sudo."
    exit 1
  fi
}

confirm_continue() {
  read -p "Continue? (yes/no): " -r
  if [[ ! $REPLY =~ ^yes$ ]]; then
    log_warn "User cancelled."
    exit 0
  fi
}

trap_cleanup() {
  log_warn "Script interrupted. Cleaning up..."
  exit 1
}

trap trap_cleanup INT TERM
