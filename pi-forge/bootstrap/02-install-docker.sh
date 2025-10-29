#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source bootstrap/utils.sh

echo "[i] Installing Docker and Docker Compose..."

# Install Docker
curl -fsSL https://get.docker.com | sh

# Add user to docker group
sudo usermod -aG docker "${USERNAME:-$USER}"

# Create Docker daemon config directory
sudo mkdir -p /etc/docker

# Configure Docker daemon
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-address-pools": [
    {
      "base": "172.80.0.0/16",
      "size": 24
    }
  ]
}
EOF

# Enable and start Docker
sudo systemctl enable docker
sudo systemctl restart docker

echo "[i] Docker installed successfully"
echo "[i] Note: You may need to logout and login for Docker group membership to take effect"
