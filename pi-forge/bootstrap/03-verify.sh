#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source bootstrap/utils.sh

echo "[i] Verifying installation..."

# Check Docker
if command -v docker >/dev/null 2>&1; then
  echo "OK Docker installed"
  docker_version=$(docker --version)
  echo "  Version: $docker_version"
else
  echo "FAIL Docker not found"
fi

# Check Docker Compose
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "OK Docker Compose available"
  compose_version=$(docker compose version)
  echo "  Version: $compose_version"
else
  echo "FAIL Docker Compose not available"
fi

# Check Docker daemon
if sudo systemctl is-active --quiet docker; then
  echo "OK Docker daemon running"
else
  echo "FAIL Docker daemon not running"
fi

# Check Docker group membership
if groups | grep -q docker; then
  echo "OK User in docker group"
else
  echo "WARNING User not in docker group (logout/login required)"
fi

# Test Docker functionality
if docker run --rm hello-world >/dev/null 2>&1; then
  echo "OK Docker functionality test passed"
else
  echo "FAIL Docker functionality test failed"
fi

# Check required tools
for tool in curl wget git jq yq envsubst ansible-vault; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "OK Tool: $tool"
  else
    echo "FAIL Missing tool: $tool"
  fi
done

# Check /srv directory
if [[ -d /srv ]]; then
  echo "OK /srv directory exists"
else
  echo "WARNING /srv directory missing (will be created as needed)"
fi

echo ""
echo "[i] Verification complete"
