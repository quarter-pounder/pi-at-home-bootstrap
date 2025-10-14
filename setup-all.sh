#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Load helpers
source scripts/utils.sh
load_env || true

# Colors
RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

trap 'echo ""; echo "${YELLOW}[!] Setup interrupted by user.${RESET}"; exit 1' INT TERM

cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║     GitLab on Raspberry Pi 5 - Off we go!                  ║
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
echo "    - Automated backups"
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
  echo ""
  echo "${YELLOW}[i] Docker installed.${RESET} Log out/in so your user joins the docker group."
  echo "${YELLOW}After re-login, run: ${RESET} ./setup-services.sh"
  exit 0
fi
