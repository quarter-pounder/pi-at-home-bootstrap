#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:-}"

if [[ -z "$REPO_URL" ]]; then
  echo "Usage: curl -sSL <raw-url-to-this-script> | bash -s <repo-url>"
  echo "Example: curl -sSL https://raw.githubusercontent.com/user/repo/main/install.sh | bash -s https://github.com/user/repo"
  exit 1
fi

echo "GitLab Pi Bootstrap - Quick Install"
echo ""

if [[ ! -f /etc/os-release ]] || ! grep -q "ID=ubuntu" /etc/os-release; then
  echo "[!] This script requires Ubuntu"
  exit 1
fi

echo "[i] Installing git..."
sudo apt update
sudo apt install -y git

echo "[i] Cloning repository..."
git clone "$REPO_URL" gitlab-bootstrap
cd gitlab-bootstrap

echo ""
echo "Repository cloned successfully!"
echo ""
echo "Next steps:"
echo "  1. cd gitlab-bootstrap"
echo "  2. cp env.example .env"
echo "  3. vim .env  # Configure your settings"
echo "  4. ./scripts/00-preflight-check.sh  # Validate setup"
echo "  5. Choose your path:"
echo "     - Path A (SD→NVMe): ./scripts/00-migrate-to-nvme.sh"
echo "     - Path B (Fresh): Already done via flash"
echo "  6. ./setup-all.sh"
echo "  7. Logout and login"
echo "  8. ./setup-services.sh"
echo ""

