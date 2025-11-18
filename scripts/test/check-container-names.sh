#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="${1:-http://192.168.0.58:9090}"

echo "=== Checking container names in metrics ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_cpu_usage_seconds_total" | \
  jq -r '.data.result[] | select(.metric.name != "" and .metric.name != "null") | .metric | "name=\(.name // "NONE") | id=\(.id // "NONE") | image=\(.image // "NONE")"' | \
  head -20

echo ""
echo "=== Checking for containers with 'forgejo' in name ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_cpu_usage_seconds_total{name=~\".*forgejo.*\"}" | \
  jq -r '.data.result[] | .metric | to_entries | map("\(.key)=\(.value)") | join(" | ")' | \
  head -10

echo ""
echo "=== All available label names ==="
curl -s "${PROMETHEUS_URL}/api/v1/label/__name__/values" | jq -r '.data[] | select(startswith("container_"))' | head -5

echo ""
echo "=== Sample container metric with all labels ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_cpu_usage_seconds_total" | \
  jq -r '.data.result[0] | .metric | to_entries | map("\(.key)=\(.value)") | join("\n")' | head -30

