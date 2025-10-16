#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

echo "==================== SYSTEM HEALTH CHECK ===================="

echo ""
echo "[i] System Information:"
uptime || true
if command -v vcgencmd >/dev/null 2>&1; then
  echo "Temperature: $(vcgencmd measure_temp)"
else
  echo "Temperature: (vcgencmd not available)"
fi
echo "Memory:"
free -h || true
echo "Disk:"
df -h / /srv 2>/dev/null || df -h /

echo ""
echo "[i] Docker Status:"
if command -v docker >/dev/null 2>&1; then
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
else
  echo "${RED}Docker not installed${RESET}"
fi

echo ""
echo "[i] GitLab Health:"
if docker ps --format '{{.Names}}' | grep -q '^gitlab$'; then
  if docker exec gitlab gitlab-rake gitlab:check SANITIZE=true >/dev/null 2>&1; then
    echo "${GREEN}GitLab is healthy${RESET}"
  else
   echo "${RED}GitLab health check failed. Checking logs..."
   docker logs gitlab --tail 50
  fi
else
  echo "${YELLOW}GitLab container not running${RESET}"
fi

echo ""
echo "[i] Service Endpoints:"
for endpoint in \
  "GitLab:http://localhost:80/-/health" \
  "Registry:http://localhost:5050/" \
  "Prometheus:http://localhost:${PROM_PORT}/-/healthy" \
  "Grafana:http://localhost:${GRAFANA_PORT}/api/health"; do
  name=$(echo "$endpoint" | cut -d: -f1)
  url=$(echo "$endpoint" | cut -d: -f2-)
  if timeout 5 curl -sf "$url" >/dev/null 2>&1; then
    echo "${GREEN}$name is responding${RESET}"
  else
    echo "${RED}$name is not responding${RESET}"
  fi
done

echo ""
echo "[i] Cloudflare Tunnel:"
if systemctl list-unit-files | grep -q '^cloudflared.service'; then
  if sudo systemctl is-active cloudflared >/dev/null 2>&1; then
    echo "${GREEN}Cloudflare Tunnel is running${RESET}"
  else
    echo "${RED}Cloudflare Tunnel is not running${RESET}"
  fi
else
  echo "${YELLOW}Cloudflared not installed${RESET}"
fi

echo ""
echo "[i] Firewall Status:"
if command -v ufw >/dev/null 2>&1; then
  sudo ufw status | head -10
else
  echo "(ufw not installed)"
fi

echo ""
echo "[i] Recent Backup:"
if [[ -d "${BACKUP_DIR:-}" ]]; then
  latest=$(ls -t "${BACKUP_DIR}/gitlab"/*_gitlab_backup.tar 2>/dev/null | head -1 || true)
  if [[ -n "${latest:-}" ]]; then
    echo "Latest backup: $(basename "$latest")"
    echo "Size: $(du -h "$latest" | cut -f1)"
    echo "Age: $(stat -c %y "$latest" | cut -d' ' -f1)"
  else
    echo "No backups found in ${BACKUP_DIR}/gitlab"
  fi
else
  echo "(Backup directory not found)"
fi

echo ""
echo "==================== END HEALTH CHECK ===================="
