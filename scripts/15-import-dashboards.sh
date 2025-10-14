#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

GRAFANA_URL="http://localhost:${GRAFANA_PORT:-3000}"
GRAFANA_USER="admin"
GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD}"

echo "Importing Grafana Dashboards"
echo "============================="
echo ""

wait_for_grafana() {
  echo "${YELLOW}Waiting for Grafana to be ready...${RESET}"
  for i in {1..30}; do
    if curl -sf "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
      echo "${GREEN}Grafana is ready${RESET}"
      return 0
    fi
    sleep 2
  done
  echo "Grafana did not start in time"
  return 1
}

import_dashboard() {
  local file=$1
  local name=$(basename "$file" .json)

  echo "Importing $name..."

  curl -s -X POST \
    -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -d @"$file" \
    "${GRAFANA_URL}/api/dashboards/db" | jq -r '.status // "error"'
}

wait_for_grafana || exit 1

echo ""
echo "${YELLOW}Importing dashboards...${RESET}"

for dashboard in config/grafana-dashboard-*.json; do
  if [[ -f "$dashboard" ]]; then
    import_dashboard "$dashboard"
  fi
done

echo ""
echo "${GREEN}Dashboard import complete!${RESET}"
echo ""
echo "Access Grafana: http://localhost:${GRAFANA_PORT}"
echo "Or via tunnel: https://grafana.${DOMAIN}"
echo "Login: admin / ${GRAFANA_ADMIN_PASSWORD}"
echo ""
echo "Available dashboards:"
echo "  - GitLab Overview"
echo "  - Raspberry Pi System Metrics"

