#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="${1:-http://192.168.0.58:9090}"

echo "=== All container_cpu_usage_seconds_total metrics (first 30) ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_cpu_usage_seconds_total" | \
  jq -r '.data.result[] | "id=\(.metric.id // "NONE") | name=\(.metric.name // "NONE") | image=\(.metric.image // "NONE") | container=\(.metric.container // "NONE")"' | \
  head -30

echo ""
echo "=== Looking for Docker container paths (containing /docker/) ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_cpu_usage_seconds_total" | \
  jq -r '.data.result[] | select(.metric.id | contains("/docker/")) | "id=\(.metric.id) | name=\(.metric.name // "NONE")"' | \
  head -10

echo ""
echo "=== Looking for containerd container paths (containing /containerd/) ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_cpu_usage_seconds_total" | \
  jq -r '.data.result[] | select(.metric.id | contains("/containerd/")) | "id=\(.metric.id) | name=\(.metric.name // "NONE")"' | \
  head -10

echo ""
echo "=== Sample metric with ALL labels ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_cpu_usage_seconds_total" | \
  jq -r '.data.result[] | select(.metric.id | contains("/docker/") or contains("/containerd/")) | .metric | to_entries | map("\(.key)=\(.value)") | join("\n")' | \
  head -40

