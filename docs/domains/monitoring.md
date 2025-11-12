# Monitoring Domain

The monitoring domain deploys Prometheus, Alertmanager, Grafana, Loki, node-exporter, cAdvisor, and Grafana Alloy to observe the Forgejo stack and the Raspberry Pi host.

## Contract
- **Lifecycle**: `make deploy DOMAIN=monitoring`
- **State**: `/srv/monitoring/{prometheus,alertmanager,grafana,loki}`
- **Networks**: `monitoring-network` (local bridge) and `forgejo-network` (shared with Forgejo, PostgreSQL, Woodpecker)
- **Outputs**:
  - Prometheus on `PORT_MONITORING_PROMETHEUS`
  - Alertmanager on `PORT_MONITORING_ALERTMANAGER`
  - Grafana on `PORT_MONITORING_GRAFANA`
  - Loki on `PORT_MONITORING_LOKI`
  - Alloy HTTP server on `PORT_MONITORING_ALLOY`

## Prometheus Targets
Prometheus now discovers services over the shared Docker bridge instead of hitting host ports. The scrape jobs include:
- `forgejo:3000/metrics` (bearer token from `FORGEJO_METRICS_TOKEN`)
- `woodpecker:9000/metrics`
- `node-exporter:9100`
- `cadvisor:8080`
- `prometheus:9090`

## Grafana Provisioning
Grafana provisions datasources with stable UIDs (`prometheus`, `loki`) and loads dashboards from `generated/monitoring/dashboards/`:
- **Pi System Overview** – CPU, memory, filesystem, and temperature panels.
- **Forgejo & Woodpecker Overview** – Service availability stats plus request/scheduler throughput.

Provisioned dashboards are available inside the "Pi Forge" folder on first boot.

## TLS Termination
Grafana continues to serve HTTP internally. Use Cloudflare Tunnel (or another edge proxy) to provide external HTTPS; set `DOMAIN` so that `GF_SERVER_ROOT_URL` renders the correct external URL.

## Host Exporters
The node-exporter textfile collector publishes Raspberry Pi specifics:
- `generated/monitoring/exporters/pi-temp-exporter.sh` – SoC temperature (`pi_cpu_temperature_celsius`).
- `generated/monitoring/exporters/pi-health-exporter.sh` – Throttling flags and core voltage (`pi_throttled_flag`, `pi_core_voltage_volts`).
- `generated/monitoring/exporters/pi-dmesg-exporter.sh` – Kernel error counters (`pi_dmesg_error_total`).

Install the helpers and schedule them via cron (run as root to access hardware commands):

```bash
sudo mkdir -p /srv/monitoring/node-exporter/textfile
sudo chmod 755 /srv/monitoring/node-exporter/textfile

sudo cp generated/monitoring/exporters/pi-temp-exporter.sh /usr/local/bin/pi-temp-exporter
sudo cp generated/monitoring/exporters/pi-health-exporter.sh /usr/local/bin/pi-health-exporter
sudo cp generated/monitoring/exporters/pi-dmesg-exporter.sh /usr/local/bin/pi-dmesg-exporter
sudo chmod +x /usr/local/bin/pi-*-exporter

cat <<'EOF' | sudo tee /etc/cron.d/pi-node-exporters
* * * * * root /usr/local/bin/pi-temp-exporter >/tmp/pi-temp-exporter.log 2>&1
* * * * * root /usr/local/bin/pi-health-exporter >/tmp/pi-health-exporter.log 2>&1
*/5 * * * * root /usr/local/bin/pi-dmesg-exporter >/tmp/pi-dmesg-exporter.log 2>&1
EOF
```

Adjust intervals or logging as needed. All scripts tolerate missing `vcgencmd` or insufficient privileges by emitting `NaN`; Prometheus treats those as "no data".

## Alerts
`prometheus-alerts.yml` reuses the legacy thresholds and adds Pi-specific safety checks:
- Temperature: warning at 80 °C, critical at 85 °C.
- Active throttling (`pi_throttled_flag{condition="throttled_now"}`) and under-voltage assertions fire critical alerts immediately.
- Voltage thresholds warn below 4.8 V and escalate below 4.7 V.
- Kernel error bursts trigger when `pi_dmesg_error_total` increases within five minutes.

These alerts complement the DR webhook rules; Alertmanager forwards incidents through the same receivers configured earlier.
