#!/usr/bin/env bash
set -Eeuo pipefail

# pi-forge Bootstrap Installer
# Minimal Ubuntu host setup with Docker-ready environment

log_info()  { echo "[i] $*"; }
log_warn()  { echo "[!] $*" >&2; }
log_error() { echo "[!] $*" >&2; }

trap 'log_error "Installation interrupted"; exit 1' INT TERM

REPO_URL="${1:-}"
BRANCH="${2:-main}"

if [[ -z "$REPO_URL" ]]; then
  echo "Usage: curl -sSL <raw-url-to-this-script> | bash -s <repo-url> [branch]"
  exit 1
fi

log_info "pi-forge Bootstrap Installer"
echo ""

if [[ ! -f /etc/os-release ]] || ! grep -q "ID=ubuntu" /etc/os-release; then
  log_error "This script requires Ubuntu."
  exit 1
fi

command -v sudo >/dev/null 2>&1 || { log_error "sudo required"; exit 1; }
command -v apt-get >/dev/null 2>&1 || { log_error "apt-get not found"; exit 1; }

# Verify sudo access
if ! sudo -n true 2>/dev/null && ! sudo -v 2>/dev/null; then
  log_error "This script requires sudo access. Please ensure sudo privileges."
  exit 1
fi

log_info "Installing git..."

# Check internet connectivity
if command -v ping >/dev/null 2>&1; then
  if ! ping -c1 -W2 github.com >/dev/null 2>&1; then
    log_error "No Internet connectivity detected (cannot reach github.com)"
    exit 1
  fi
else
  log_warn "ping not available, skipping connectivity check"
fi

sudo apt-get update -y
sudo apt-get install -y git

if [[ -d pi-forge ]]; then
  log_error "Directory 'pi-forge' already exists. Remove or rename before continuing."
  exit 1
fi

log_info "Cloning repository..."
git clone --branch "$BRANCH" --depth=1 "$REPO_URL" pi-forge
cd pi-forge

echo ""
log_info "Repository cloned successfully!"
cat <<EOF

Next steps (you are now in the pi-forge directory):

  1. (Optional) sudo bash bootstrap/00-migrate-to-nvme.sh   # Migrate to NVMe boot
  2. sudo bash bootstrap/01-preflight.sh      # Validate setup
  3. sudo bash bootstrap/02-install-core.sh   # Install core dependencies
  4. sudo bash bootstrap/03-install-docker.sh # Install Docker
  5. sudo bash bootstrap/04-optimize-docker.sh # Optimize Docker for Pi
  6. bash bootstrap/05-verify.sh              # Verify installation
  7. sudo bash bootstrap/06-security-hardening.sh # Optional: apply SSH/fail2ban/sysctl hardening

Bootstrap ready.
EOF
