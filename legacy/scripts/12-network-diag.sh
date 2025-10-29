#!/usr/bin/env bash
set -euo pipefail

GREEN=$(tput setaf 2); RED=$(tput setaf 1); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

echo "Network Diagnostics"
echo "==================="
echo ""

check() {
  if $1 >/dev/null 2>&1; then
    echo "${GREEN}[OK]${RESET} $2"
  else
    echo "${RED}[FAIL]${RESET} $2"
  fi
}

echo "1. Network Interfaces"
ip -br addr show | grep -v "lo"

echo ""
echo "2. Internet Connectivity"
check "ping -c 1 8.8.8.8" "Can reach Google DNS (8.8.8.8)"
check "ping -c 1 1.1.1.1" "Can reach Cloudflare DNS (1.1.1.1)"

echo ""
echo "3. DNS Resolution"
check "nslookup github.com" "Can resolve github.com"
check "nslookup gitlab.com" "Can resolve gitlab.com"

echo ""
echo "4. External Connectivity"
check "curl -s --max-time 5 https://github.com" "Can reach GitHub (HTTPS)"
check "curl -s --max-time 5 https://gitlab.com" "Can reach GitLab.com (HTTPS)"

echo ""
echo "5. Local GitLab Services"
check "curl -sfk https://localhost:443/-/health" "GitLab web (HTTPS)"
check "curl -sf http://localhost:9090/-/healthy" "Prometheus (port 9090)"
check "curl -sf http://localhost:3000/api/health" "Grafana (port 3000)"

echo ""
echo "6. Docker Networks"
docker network ls

echo ""
echo "7. Container Connectivity"
if docker ps --format '{{.Names}}' | grep -q gitlab; then
  echo "Testing inter-container communication..."
  docker exec gitlab ping -c 1 prometheus >/dev/null 2>&1 && \
    echo "${GREEN}[OK]${RESET} GitLab can reach Prometheus" || \
    echo "${RED}[FAIL]${RESET} GitLab cannot reach Prometheus"
fi

echo ""
echo "8. Cloudflare Tunnel Status"
if systemctl is-active cloudflared >/dev/null 2>&1; then
  echo "${GREEN}[OK]${RESET} Cloudflare Tunnel is running"
  sudo journalctl -u cloudflared -n 5 --no-pager | grep -i "connection\|registered"
else
  echo "${YELLOW}WARNING${RESET} Cloudflare Tunnel is not running"
fi

echo ""
echo "9. Firewall Status"
sudo ufw status | head -10

echo ""
echo "10. Open Ports"
sudo ss -tlnp | grep -E ":(80|443|22|3000|9090|2222)" || echo "No services listening on expected ports"

echo ""
echo "11. Network Performance"
echo "Testing download speed..."
if command -v wget >/dev/null; then
  wget -O /dev/null http://cachefly.cachefly.net/10mb.test 2>&1 | grep -E "saved|\/s"
else
  echo "wget not installed, skipping speed test"
fi

echo ""
echo "${GREEN}Diagnostics complete!${RESET}"

