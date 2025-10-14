#!/usr/bin/env bash
set -euo pipefail

cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║     GitLab on Raspberry Pi 5 - Off we go!                  ║
╚════════════════════════════════════════════════════════════╝
EOF

if [[ ! -f .env ]]; then
  echo "[!] .env file not found. Please copy env.example to .env and configure it."
  exit 1
fi

source .env

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

echo ""
echo "Step 1/7: Post-boot system setup..."
./scripts/01-post-boot-setup.sh

echo ""
echo "Step 2/7: Security hardening..."
./scripts/02-security-hardening.sh

echo ""
echo "Step 3/7: Installing Docker..."
./scripts/03-install-docker.sh

echo ""
echo "[i] Docker installed. You need to logout and login again for group changes."
echo "[!] After re-login, run this script again to continue from Step 4."
echo ""
read -p "Press Enter to logout now, or Ctrl+C to cancel..."
kill -HUP $PPID

