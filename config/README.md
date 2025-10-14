# Configuration Files

## Grafana Dashboards

Pre-configured Grafana dashboards for monitoring:

### `grafana-dashboard-gitlab.json`
GitLab-specific metrics:
- HTTP request rate
- Memory usage
- CI/CD job status
- Overall service health

### `grafana-dashboard-system.json`
Raspberry Pi system metrics:
- CPU usage
- Memory usage
- Disk usage
- Temperature monitoring
- Network traffic

**Import**: Run `./scripts/15-import-dashboards.sh` after setup

## Prometheus Alerts

Prometheus is just amazing and it makes you wonder why some people pay for legacy alternatives willingly.

### `prometheus-alerts.yml`
Alert rules for critical conditions:

**System Alerts:**
- High CPU (>80% for 5min)
- High memory (>85% for 5min)
- Low disk space (>85% for 5min)
- Critical disk (>95% for 1min)
- High temperature (>80°C for 2min)
- Critical temperature (>85°C for 1min)

**GitLab Alerts:**
- GitLab down (>2min)
- High GitLab memory (>3GB for 5min)
- Runner down (>5min)

**Docker Alerts:**
- Container down (>2min)
- High container memory (>1GB for 5min)

Alerts are evaluated by Prometheus every 30 seconds.

## Other Configs

- `docker-daemon.json` - Docker log rotation and storage driver
- `gitlab.rb.template` - GitLab settings optimized for Pi 5
- `prometheus.yml` - Prometheus scrape configuration
- `grafana-datasource.yml` - Auto-configure Prometheus as datasource
- `fail2ban-*.conf` - Brute-force protection for SSH and GitLab
- `runner-config.toml.template` - GitLab Runner configuration

## Customization

All configs use environment variables from `.env` for easy customization.

Edit templates, then restart services:
```bash
cd compose
docker compose -f gitlab.yml restart
docker compose -f monitoring.yml restart
```

