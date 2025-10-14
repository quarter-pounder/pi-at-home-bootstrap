#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

echo "==================== SYSTEM HEALTH CHECK ===================="

echo ""
echo "[i] System Information:"
uptime
echo "Temperature: $(vcgencmd measure_temp)"
echo "Memory:"
free -h
echo "Disk:"
df -h / /srv

echo ""
echo "[i] Docker Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "[i] GitLab Health:"
if docker exec gitlab gitlab-rake gitlab:check SANITIZE=true 2>/dev/null; then
  echo "✓ GitLab is healthy"
else
  echo "✗ GitLab health check failed"
fi

echo ""
echo "[i] Service Endpoints:"
for endpoint in \
  "GitLab:http://localhost:80/-/health" \
  "Registry:http://localhost:5050/" \
  "Prometheus:http://localhost:${PROM_PORT}/-/healthy" \
  "Grafana:http://localhost:${GRAFANA_PORT}/api/health"; do

  name=$(echo $endpoint | cut -d: -f1)
  url=$(echo $endpoint | cut -d: -f2-)

  if curl -sf "$url" >/dev/null 2>&1; then
    echo "✓ $name is responding"
  else
    echo "✗ $name is not responding"
  fi
done

echo ""
echo "[i] Cloudflare Tunnel:"
if sudo systemctl is-active cloudflared >/dev/null 2>&1; then
  echo "✓ Cloudflare Tunnel is running"
else
  echo "✗ Cloudflare Tunnel is not running"
fi

echo ""
echo "[i] Firewall Status:"
sudo ufw status | head -10

echo ""
echo "[i] Recent Backup:"
if [[ -d "${BACKUP_DIR}/gitlab" ]]; then
  latest=$(ls -t "${BACKUP_DIR}/gitlab"/*_gitlab_backup.tar 2>/dev/null | head -1)
  if [[ -n "$latest" ]]; then
    echo "Latest backup: $(basename "$latest")"
    echo "Size: $(du -h "$latest" | cut -f1)"
    echo "Age: $(stat -c %y "$latest" | cut -d' ' -f1)"
  else
    echo "No backups found"
  fi
fi

echo ""
echo "==================== END HEALTH CHECK ===================="

