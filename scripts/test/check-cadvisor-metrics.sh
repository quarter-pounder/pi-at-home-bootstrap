#!/usr/bin/env bash
set -euo pipefail

# Diagnostic script to check what cadvisor exposes in Prometheus

PROMETHEUS_URL="${PROMETHEUS_URL:-http://192.168.0.58:9090}"

echo "=== Checking container_cpu_usage_seconds_total metrics ==="
echo ""
echo "All metrics with 'docker' in id:"
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode 'query=container_cpu_usage_seconds_total{job="cadvisor",id=~".*docker.*"}' \
  | jq -r '.data.result[] | "\(.metric.id) | \(.metric | to_entries | map("\(.key)=\(.value)") | join(", "))"' \
  | head -20

echo ""
echo "All unique id patterns:"
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode 'query=container_cpu_usage_seconds_total{job="cadvisor"}' \
  | jq -r '.data.result[].metric.id' \
  | sort -u \
  | head -20

echo ""
echo "=== Checking container_name_info ==="
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode 'query=container_name_info' \
  | jq -r '.data.result[] | "\(.metric.container_id) -> \(.metric.container_name)"' \
  | head -20

echo ""
echo "=== Checking if forgejo container exists ==="
curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode 'query=container_name_info{container_name="forgejo"}' \
  | jq '.'

echo ""
echo "=== Checking if forgejo CPU metrics exist (any pattern) ==="
FORGEJO_ID=$(curl -s "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode 'query=container_name_info{container_name="forgejo"}' \
  | jq -r '.data.result[0].metric.container_id // empty')

if [[ -n "${FORGEJO_ID}" ]]; then
  echo "Forgejo container ID: ${FORGEJO_ID}"
  echo "Searching for metrics with this ID..."
  curl -s "${PROMETHEUS_URL}/api/v1/query" \
    --data-urlencode "query=container_cpu_usage_seconds_total{job=\"cadvisor\",id=~\".*${FORGEJO_ID}.*\"}" \
    | jq '.data.result | length'
else
  echo "Forgejo container not found in container_name_info"
fi

