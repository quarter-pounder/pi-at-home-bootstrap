#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

echo "[i] Setting up Pi-hole ad blocker..."

# Check if PIHOLE_WEB_PASSWORD is set
if [[ -z "${PIHOLE_WEB_PASSWORD:-}" ]]; then
  echo "[!] PIHOLE_WEB_PASSWORD not set in .env"
  echo "Please add a password for Pi-hole web interface:"
  echo "  PIHOLE_WEB_PASSWORD=your_secure_password"
  exit 1
fi

# Get Pi IP address
PI_IP=$(hostname -I | awk '{print $1}')

# Create directories
echo "[i] Creating ad blocker directories..."
sudo mkdir -p /srv/pihole/{pihole,dnsmasq.d}
sudo mkdir -p /srv/unbound
sudo chown -R 1000:1000 /srv/pihole
sudo chown -R 1000:1000 /srv/unbound

# Download root hints for Unbound
echo "[i] Downloading DNS root hints..."
sudo wget -O /srv/unbound/root.hints https://www.internic.net/domain/named.cache

# Create Unbound configuration
echo "[i] Creating Unbound configuration..."
sudo cp config/unbound.conf /srv/unbound/unbound.conf

# Update Pi-hole configuration with Pi IP
echo "[i] Updating Pi-hole configuration..."
sed -i "s/\${PI_IP:-192.168.1.100}/$PI_IP/g" compose/adblocker.yml

# Start ad blocker services
echo "[i] Starting ad blocker services..."
cd compose
docker compose -f adblocker.yml up -d

# Wait for services to start
echo "[i] Waiting for services to start..."
sleep 30

# Check if Pi-hole is running
if docker ps --format '{{.Names}}' | grep -q '^pihole$'; then
  echo "[i] Pi-hole is running"
else
  echo "[!] Pi-hole failed to start"
  exit 1
fi

# Check if Unbound is running
if docker ps --format '{{.Names}}' | grep -q '^unbound$'; then
  echo "[i] Unbound is running"
else
  echo "[!] Unbound failed to start"
  exit 1
fi

# Test DNS resolution
echo "[i] Testing DNS resolution..."
if nslookup google.com 127.0.0.1 >/dev/null 2>&1; then
  echo "[i] DNS resolution working"
else
  echo "[!] DNS resolution failed"
fi

# Create network configuration helper
echo "[i] Creating network configuration helper..."
cat > /srv/pihole/configure-network.sh <<EOF
#!/bin/bash
echo "Pi-hole Network Configuration"
echo "============================="
echo ""
echo "Pi-hole is running at: http://$PI_IP:8080"
echo "Web interface password: ${PIHOLE_WEB_PASSWORD}"
echo ""
echo "To use Pi-hole as your DNS server:"
echo "1. Go to your router's admin panel"
echo "2. Set DNS server to: $PI_IP"
echo "3. Or configure each device to use: $PI_IP"
echo ""
echo "Test ad blocking:"
echo "  nslookup doubleclick.net $PI_IP"
echo "  (Should return 0.0.0.0 if blocking works)"
echo ""
echo "Pi-hole admin: http://$PI_IP:8080/admin"
EOF

chmod +x /srv/pihole/configure-network.sh

# Update Cloudflare tunnel to include Pi-hole
echo "[i] Updating Cloudflare tunnel configuration..."
if [[ -f /etc/cloudflared/config.yml ]]; then
  # Add Pi-hole to tunnel config
  sudo tee -a /etc/cloudflared/config.yml >/dev/null <<EOF
  - hostname: pihole.${DOMAIN}
    service: http://localhost:8080
EOF

  # Restart Cloudflare tunnel
  sudo systemctl restart cloudflared
  echo "[i] Cloudflare tunnel updated with Pi-hole"
fi

# Create monitoring integration
echo "[i] Creating monitoring integration..."
cat > /srv/pihole/monitor.sh <<'EOF'
#!/bin/bash
# Pi-hole monitoring script

PIHOLE_IP="127.0.0.1"
PIHOLE_PORT="8080"

# Check if Pi-hole is responding
if curl -sf "http://${PIHOLE_IP}:${PIHOLE_PORT}/admin/api.php?summary" >/dev/null 2>&1; then
  echo "Pi-hole: OK"

  # Get statistics
  STATS=$(curl -s "http://${PIHOLE_IP}:${PIHOLE_PORT}/admin/api.php?summary")
  QUERIES=$(echo "$STATS" | jq -r '.dns_queries_today // 0')
  BLOCKED=$(echo "$STATS" | jq -r '.ads_blocked_today // 0')
  PERCENT=$(echo "$STATS" | jq -r '.ads_percentage_today // 0')

  echo "Queries today: $QUERIES"
  echo "Blocked ads: $BLOCKED"
  echo "Block percentage: ${PERCENT}%"
else
  echo "Pi-hole: FAILED"
  exit 1
fi
EOF

chmod +x /srv/pihole/monitor.sh

# Add Pi-hole to health check
echo "[i] Adding Pi-hole to health check..."
if ! grep -q "Pi-hole" scripts/21-health-check.sh; then
  sed -i '/echo "\[i\] Service Endpoints:"/a\\n  "Pi-hole:http://localhost:8080/admin/api.php?summary" \\' scripts/21-health-check.sh
fi

echo ""
echo "Pi-hole ad blocker setup complete!"
echo ""
echo "Access Pi-hole:"
echo "  Web interface: http://$PI_IP:8080/admin"
echo "  Password: ${PIHOLE_WEB_PASSWORD}"
echo "  External: https://pihole.${DOMAIN}/admin"
echo ""
echo "Network configuration:"
echo "  DNS server: $PI_IP"
echo "  Run: /srv/pihole/configure-network.sh"
echo ""
echo "Monitoring:"
echo "  Check status: /srv/pihole/monitor.sh"
echo "  Health check: ./scripts/21-health-check.sh"
echo ""
echo "To configure your network:"
echo "  1. Set router DNS to: $PI_IP"
echo "  2. Or configure devices individually"
echo "  3. Test with: nslookup doubleclick.net $PI_IP"
