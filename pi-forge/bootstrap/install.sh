#!/usr/bin/env bash
set -euo pipefail

# Bootstrap installer for pi-forge
# Minimal host setup with Docker ready

REPO_URL="${1:-}"

if [[ -z "$REPO_URL" ]]; then
  echo "Usage: curl -sSL <raw-url-to-this-script> | bash -s <repo-url>"
  exit 1
fi

echo "pi-forge Bootstrap Installer"
echo ""

if [[ ! -f /etc/os-release ]] || ! grep -q "ID=ubuntu" /etc/os-release; then
  echo "[!] This script requires Ubuntu"
  exit 1
fi

echo "[i] Installing git..."
sudo apt update
sudo apt install -y git

echo "[i] Cloning repository..."
git clone "$REPO_URL" pi-forge
cd pi-forge

echo ""
echo "Repository cloned successfully!"
echo ""
echo "Next steps:"
echo "  1. cd pi-forge"
echo "  2. cp config-registry/env/base.env.example config-registry/env/base.env"
echo "  3. vim config-registry/env/base.env  # Configure your settings"
echo "  4. bash bootstrap/00-preflight.sh  # Validate setup"
echo "  5. bash bootstrap/01-install-core.sh  # Install core dependencies"
echo "  6. bash bootstrap/02-install-docker.sh  # Install Docker"
echo "  7. bash bootstrap/03-verify.sh  # Verify installation"
echo "  8. Logout and login to activate Docker group"
echo ""
