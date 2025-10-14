#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

echo "[i] Verifying cloud-init completed..."
cloud-init status --wait

echo "[i] Checking swap configuration..."
swapon --show

echo "[i] Verifying firewall status..."
sudo ufw status

echo "[i] Updating system packages..."
sudo apt update
sudo apt upgrade -y

echo "[i] Installing additional utilities..."
sudo apt install -y \
  python3-pip \
  jq \
  tree \
  dnsutils \
  sysstat

echo "[i] Configuring log rotation..."
sudo tee /etc/logrotate.d/gitlab-custom >/dev/null <<EOF
/srv/gitlab/logs/**/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

echo "[i] Setting up temperature monitoring..."
sudo tee /usr/local/bin/check-temp >/dev/null <<'EOF'
#!/bin/bash
temp=$(vcgencmd measure_temp | grep -oP '\d+\.\d+')
if (( $(echo "$temp > 80" | bc -l) )); then
    logger -t pi-temp "WARNING: CPU temperature is ${temp}C"
fi
echo "CPU Temperature: ${temp}C"
EOF

sudo chmod +x /usr/local/bin/check-temp

echo "[i] Creating monitoring cron job..."
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/check-temp") | crontab -

echo "[i] Post-boot setup complete. System ready for service installation."

