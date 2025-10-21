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
# Try multiple temperature sources for Pi 5 compatibility
if command -v vcgencmd >/dev/null 2>&1; then
  temp_result=$(vcgencmd measure_temp 2>/dev/null || echo "")
  if [[ -n "$temp_result" ]]; then
    echo "Temperature: $temp_result"
  elif [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
    temp_c=$(echo "scale=1; $temp_raw/1000" | bc 2>/dev/null || echo "n/a")
    echo "Temperature: ${temp_c}°C"
  else
    echo "Temperature: Unable to read"
  fi
elif [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
  temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
  temp_c=$(echo "scale=1; $temp_raw/1000" | bc 2>/dev/null || echo "n/a")
  echo "Temperature: ${temp_c}°C"
else
  echo "Temperature: Unable to read"
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
  "GitLab:https://localhost:443/" \
  "Registry:http://localhost:5050/" \
  "Prometheus:http://localhost:${PROM_PORT:-9090}/-/healthy" \
  "Alertmanager:http://localhost:9093/-/healthy" \
  "Grafana:http://localhost:${GRAFANA_PORT:-3000}/api/health" \
  "Loki:http://localhost:3100/ready" \
  "Alloy:http://localhost:12345/-/healthy" \
  "Pi-hole:http://localhost:8080/admin/api.php?summary"; do
  name=$(echo "$endpoint" | cut -d: -f1)
  url=$(echo "$endpoint" | cut -d: -f2-)
  if timeout 5 curl -sf -k "$url" >/dev/null 2>&1; then
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
echo "[i] DR System:"
if systemctl list-unit-files | grep -q '^prometheus-webhook-receiver.service'; then
  if sudo systemctl is-active prometheus-webhook-receiver >/dev/null 2>&1; then
    echo "${GREEN}DR webhook receiver is running${RESET}"
    if curl -s http://localhost:8081/status >/dev/null 2>&1; then
      echo "${GREEN}DR status endpoint is responding${RESET}"
    else
      echo "${YELLOW}DR status endpoint is not responding${RESET}"
    fi
  else
    echo "${RED}DR webhook receiver is not running${RESET}"
  fi
else
  echo "${YELLOW}DR system not installed${RESET}"
fi

echo ""
echo "[i] Recent Backup:"
if [[ -d "${BACKUP_DIR:-/srv/backups}/gitlab" ]]; then
  latest_backup=$(find "${BACKUP_DIR:-/srv/backups}/gitlab" -name "gitlab-backup-*.tar" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
  if [[ -n "$latest_backup" ]]; then
    backup_date=$(stat -c %y "$latest_backup" 2>/dev/null | cut -d' ' -f1)
    echo "Latest backup: $backup_date"
  else
    echo "${YELLOW}No backups found${RESET}"
  fi
else
  echo "${YELLOW}Backup directory not found${RESET}"
fi

echo ""
echo "[i] Firewall Status:"
if command -v ufw >/dev/null 2>&1; then
  sudo ufw status | head -10
else
  echo "(ufw not installed)"
fi

echo ""
echo "==================== END HEALTH CHECK ===================="
