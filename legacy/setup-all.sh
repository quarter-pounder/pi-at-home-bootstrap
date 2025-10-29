#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Load helpers
source scripts/utils.sh
load_env || true

# Colors
RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

trap 'echo ""; echo "${YELLOW}[!] Setup interrupted by user.${RESET}"; exit 1' INT TERM

cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║     Pi 5 at Home             - Off we go!                  ║
╚════════════════════════════════════════════════════════════╝
EOF

if [[ ! -f .env ]]; then
  echo "${RED}[!] .env file not found. Copy env.example to .env and configure it.${RESET}"
  exit 1
fi

START_STEP=${1:-1}

echo ""
echo "[i] This script will set up:"
echo "    - System hardening and security"
echo "    - Docker and dependencies"
echo "    - GitLab CE with container registry"
echo "    - Prometheus + Grafana monitoring"
echo "    - Automated backups (GCP/AWS)"
echo ""
read -p "Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
  echo "Setup cancelled"
  exit 0
fi

step() {
  echo ""
  echo "──────────────────────────────────────────────"
  echo "${YELLOW}Step $1:${RESET} $2"
  echo "──────────────────────────────────────────────"
}

if (( START_STEP <= 1 )); then
  step 1 "Post-boot system setup..."
  ./scripts/01-post-boot-setup.sh
fi

if (( START_STEP <= 2 )); then
  step 2 "Security hardening..."
  ./scripts/02-security-hardening.sh
fi

if (( START_STEP <= 3 )); then
  step 3 "Installing Docker..."
  ./scripts/03-install-docker.sh

  # Check if running from SD card and offer optimization
  if [[ -b /dev/mmcblk0 ]] && [[ ! -b /dev/nvme0n1 ]]; then
    echo ""
    echo "${YELLOW}[!] Detected SD card usage (no NVMe found)${RESET}"
    echo "[i] SD cards have limited write cycles. Consider optimizing for longevity."
    read -p "Run SD card optimization? (yes/no): " -r
    if [[ $REPLY =~ ^yes$ ]]; then
      ./scripts/00-optimize-sd-card.sh
    fi
  fi

  echo ""
  echo "${YELLOW}[i] Docker installed.${RESET} Log out/in so your user joins the docker group."
  echo "${YELLOW}After re-login, run: ${RESET} ./setup-services.sh"
  exit 0
fi
