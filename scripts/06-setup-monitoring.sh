#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

echo "[i] Creating monitoring directories..."
sudo mkdir -p /srv/prometheus
sudo mkdir -p /srv/grafana
sudo chown -R 65534:65534 /srv/prometheus
sudo chown -R 472:472 /srv/grafana

echo "[i] Starting monitoring services..."
cd compose
docker compose -f monitoring.yml up -d

echo "[i] Waiting for services to start..."
sleep 10

echo "[i] Verifying Prometheus..."
curl -s http://localhost:${PROM_PORT}/-/healthy || echo "[!] Prometheus not responding"

echo "[i] Verifying Grafana..."
curl -s http://localhost:${GRAFANA_PORT}/api/health || echo "[!] Grafana not responding"

echo "[i] Monitoring stack deployed!"
echo "[i] Prometheus: http://localhost:${PROM_PORT}"
echo "[i] Grafana: http://localhost:${GRAFANA_PORT}"
echo "[i] Grafana admin password: ${GRAFANA_ADMIN_PASSWORD}"

