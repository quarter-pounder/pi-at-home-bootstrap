#!/usr/bin/env bash
set -euo pipefail
source scripts/utils.sh
load_env

echo "[i] Installing Docker and Compose..."
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "${USERNAME}"
sudo mkdir -p /etc/docker
sudo cp config/docker-daemon.json /etc/docker/daemon.json
sudo systemctl enable docker
sudo systemctl restart docker
