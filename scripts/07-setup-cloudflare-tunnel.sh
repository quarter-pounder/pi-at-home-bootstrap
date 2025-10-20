#!/usr/bin/env bash

# Note to self:
# Once migrating configs on tf dashboard, there is no going back
# Changes in local config.yml would not affect the actual congfigs

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
  echo "[!] CLOUDFLARE_TUNNEL_TOKEN not set in .env"
  echo ""
  echo "Create a Cloudflare Tunnel:"
  echo "1. Go to https://one.dash.cloudflare.com/"
  echo "2. Navigate to Networks > Tunnels"
  echo "3. Create a new tunnel named '${CLOUDFLARE_TUNNEL_NAME}'"
  echo "4. Copy the tunnel token"
  echo "5. Add to .env: CLOUDFLARE_TUNNEL_TOKEN=your_token_here"
  echo ""
  echo "Configure tunnel routes:"
  echo "  gitlab.${DOMAIN} -> http://localhost:80"
  echo "  registry.${DOMAIN} -> http://localhost:5050"
  echo "  grafana.${DOMAIN} -> http://localhost:${GRAFANA_PORT}"
  exit 1
fi

echo "[i] Installing Cloudflare Tunnel..."
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared.deb
rm cloudflared.deb

echo "[i] Creating tunnel configuration..."
sudo mkdir -p /etc/cloudflared
sudo tee /etc/cloudflared/config.yml >/dev/null <<EOF
tunnel: ${CLOUDFLARE_TUNNEL_NAME}
credentials-file: /etc/cloudflared/cert.json

ingress:
  - hostname: gitlab.${DOMAIN}
    service: http://localhost:80
  - hostname: registry.${DOMAIN}
    service: http://localhost:5050
  - hostname: grafana.${DOMAIN}
    service: http://localhost:${GRAFANA_PORT}
  - service: http_status:404
EOF

echo "[i] Installing tunnel as systemd service..."
sudo cloudflared service install "${CLOUDFLARE_TUNNEL_TOKEN}"

echo "[i] Starting Cloudflare Tunnel..."
sudo systemctl enable cloudflared
sudo systemctl start cloudflared

echo "[i] Checking tunnel status..."
sudo systemctl status cloudflared --no-pager

echo "[i] Cloudflare Tunnel setup complete!"
echo "[i] Your services should be accessible at:"
echo "    - https://gitlab.${DOMAIN}"
echo "    - https://registry.${DOMAIN}"
echo "    - https://grafana.${DOMAIN}"

