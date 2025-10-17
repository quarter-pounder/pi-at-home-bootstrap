#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

echo "[i] Creating monitoring directories..."
sudo mkdir -p /srv/prometheus
sudo mkdir -p /srv/grafana
sudo mkdir -p /srv/loki
sudo mkdir -p /srv/alertmanager
sudo chown -R 65534:65534 /srv/prometheus
sudo chown -R 472:472 /srv/grafana
sudo chown -R 10001:10001 /srv/loki
sudo chown -R 65534:65534 /srv/alertmanager

echo "[i] Starting monitoring services..."
cd compose
docker compose -f monitoring.yml up -d

echo "[i] Waiting for services to start..."
sleep 10

echo "[i] Verifying Prometheus..."
curl -s http://localhost:${PROM_PORT}/-/healthy || echo "[!] Prometheus is not responding"

echo "[i] Verifying Grafana..."
curl -s http://localhost:${GRAFANA_PORT}/api/health || echo "[!] Grafana is not responding"

echo "[i] Verifying Loki..."
curl -s http://localhost:3100/ready || echo "[!] Loki is not responding"

echo "[i] Verifying Alloy..."
curl -s http://localhost:12345/-/healthy || echo "[!] Alloy is not responding"

echo "[i] Verifying Alertmanager..."
curl -s http://localhost:9093/-/healthy || echo "[!] Alertmanager is not responding"

echo "[i] Monitoring stack deployed!"
echo "[i] Prometheus: http://localhost:${PROM_PORT}"
echo "[i] Grafana: http://localhost:${GRAFANA_PORT}"
echo "[i] Loki: http://localhost:3100"
echo "[i] Alloy: http://localhost:12345"
echo "[i] Alertmanager: http://localhost:9093"
echo "[i] Grafana admin password: ${GRAFANA_ADMIN_PASSWORD}"

