#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="${1:-http://192.168.0.58:9090}"

echo "=== Checking container_cpu_usage_seconds_total labels ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_cpu_usage_seconds_total" | \
  jq -r '.data.result[] | select(.metric.name != "") | .metric | "\(.name) | compose_service=\(.container_label_com_docker_compose_service // "NONE") | id=\(.id // "NONE")"' | \
  head -20

echo ""
echo "=== Checking for forgejo container specifically ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_cpu_usage_seconds_total{name=~\".*forgejo.*\"}" | \
  jq -r '.data.result[] | .metric | to_entries | map("\(.key)=\(.value)") | join(" | ")' | \
  head -5

echo ""
echo "=== Checking all container labels ==="
curl -s "${PROMETHEUS_URL}/api/v1/label/__name__/values" | jq -r '.data[] | select(startswith("container_"))' | head -10

