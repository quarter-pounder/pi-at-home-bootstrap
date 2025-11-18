#!/usr/bin/env bash
set -euo pipefail

PROMETHEUS_URL="${1:-http://192.168.0.58:9090}"

echo "=== Checking cadvisor container ==="
docker ps --filter "name=monitoring-cadvisor" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Checking cadvisor logs (last 20 lines) ==="
docker logs --tail 20 monitoring-cadvisor 2>&1 || echo "Container not running or not found"

echo ""
echo "=== Testing cadvisor metrics endpoint ==="
curl -s "http://localhost:8080/metrics" 2>&1 | head -20 || echo "Cannot reach cadvisor:8080"

echo ""
echo "=== Checking if Prometheus can scrape cadvisor ==="
curl -s "${PROMETHEUS_URL}/api/v1/targets" | jq -r '.data.activeTargets[] | select(.job == "cadvisor") | {job, health, lastError, lastScrape}' || echo "Cannot query Prometheus"

echo ""
echo "=== Checking for container_cpu_usage_seconds_total metric ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_cpu_usage_seconds_total" | jq -r '.data.result | length' | xargs -I {} echo "Found {} time series" || echo "Cannot query Prometheus"

echo ""
echo "=== Checking for container_last_seen metric ==="
curl -s "${PROMETHEUS_URL}/api/v1/query?query=container_last_seen" | jq -r '.data.result | length' | xargs -I {} echo "Found {} time series" || echo "Cannot query Prometheus"

