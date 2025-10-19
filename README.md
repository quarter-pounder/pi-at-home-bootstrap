# Pi at Home Bootstrap (with GitLab)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Platform: Raspberry Pi 5](https://img.shields.io/badge/Platform-Raspberry%20Pi%205-orange)
![Ubuntu: 24.04 LTS](https://img.shields.io/badge/Ubuntu-24.04%20LTS-purple)
![Status: Testing](https://img.shields.io/badge/Status-Testing-yellow)

My setup for Raspberry Pi 5 featuring GitLab, monitoring, ad blocking, disaster recovery, and cloud integration.

Yes, we have GitLab at home.

---

## Directory Structure

```
pi-at-home-bootstrap/
├── backup/                    # Backup and restore scripts
│   ├── backup.sh
│   ├── restore.sh
│   └── setup-cron.sh
├── cloudinit/                 # Cloud-init templates for fresh flash
│   ├── meta-data.template
│   ├── network-config.template
│   └── user-data.template
├── compose/                   # Docker Compose configurations
│   ├── gitlab.yml
│   ├── monitoring.yml
│   └── adblocker.yml
├── config/                    # Service configurations
│   ├── docker-daemon.json
│   ├── gitlab.rb.template
│   ├── prometheus.yml
│   ├── grafana-datasource.yml
│   ├── loki.yml
│   ├── alloy.river
│   ├── unbound.conf
│   └── fail2ban-*.conf
├── examples/                  # CI/CD templates
│   ├── gitlab-ci-docker.yml
│   ├── gitlab-ci-nodejs.yml
│   └── gitlab-ci-python.yml
├── scripts/                   # Setup and maintenance scripts
│   ├── 00-preflight-check.sh
│   ├── 00-migrate-to-nvme.sh
│   ├── 00-flash-nvme.sh
│   ├── 01-post-boot-setup.sh
│   ├── 02-security-hardening.sh
│   ├── 03-install-docker.sh
│   ├── 04-setup-gitlab.sh
│   ├── 05-register-runner.sh
│   ├── 06-setup-monitoring.sh
│   ├── 07-setup-cloudflare-tunnel.sh
│   ├── 08-health-check.sh
│   ├── 09-update-services.sh
│   ├── 10-benchmark.sh
│   ├── 11-network-diag.sh
│   ├── 12-scale-resources.sh
│   ├── 13-setup-lfs.sh
│   ├── 14-add-runner.sh
│   ├── 15-import-dashboards.sh
│   ├── 16-setup-terraform.sh
│   ├── 17-setup-gitlab-mirror.sh
│   ├── 18-setup-dr-webhook.sh
│   ├── 19-setup-complete-dr.sh
│   ├── 20-setup-adblocker.sh
│   ├── 99-cleanup.sh
│   └── utils.sh
├── terraform/                 # Infrastructure as Code
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── cloudflare/
│       ├── aws/
│       └── gcp/
├── .env.example              # Environment variables template
├── .gitignore
├── install.sh                # One-liner installation
├── setup-all.sh              # Automated setup
├── setup-services.sh         # Service deployment
├── README.md
├── SETUP-CHECKLIST.md
├── SETUP-PATH-A.md
├── SETUP-PATH-B.md
├── MANIFEST.txt
├── FEATURES.md
└── IMPROVEMENTS.md
```

---

## Prerequisites

- Raspberry Pi 5 (I went with 8GB)
- NVMe drive or high-quality SD card (NVMe works better in the long term, SD card wears out quickly)
- Domain name with Cloudflare DNS
- Cloudflare account (free tier should do the trick)

---

## Features

- Ubuntu Server ARM64 automated flash with cloud-init
- Docker and Docker Compose
- GitLab CE with container registry
- GitLab Runner with Docker executor
- Prometheus + Grafana + Loki + Alloy monitoring stack
- Cloudflare Tunnel for secure remote access
- Pi-hole ad blocker for network-wide protection
- Automated backup to GCP/AWS or local storage
- GitLab Cloud mirroring for disaster recovery
- Terraform for cloud infrastructure management
- Security hardening (UFW, fail2ban, SSH)
- Temperature and health monitoring

---

## Setup Paths

| Scenario | Recommended Path |
|-----------|------------------|
| Already running Ubuntu from SD card | **Path A** |
| Starting fresh or flashing NVMe directly | **Path B** |
| Rebuilding from backup | Path B, then restore |

> **Note:** All scripts assume you're running from the project root directory.
> To be safe:
> ```bash
> cd ~/pi-at-home-bootstrap
> ```

---

## Quick Start

Choose a setup path:

### Path A: Already Running Ubuntu on SD Card (My case)

```bash
# 1. On Pi (running from SD card)
git clone <this-repo> pi-at-home-bootstrap
cd pi-at-home-bootstrap
cp env.example .env
vim .env  # Fill in all variables

# Optional: Run pre-flight checks
./scripts/00-preflight-check.sh

# 2. Migrate to NVMe
./scripts/00-migrate-to-nvme.sh
# Poweroff, remove SD card, boot from NVMe

# 3. After booting from NVMe
cd pi-at-home-bootstrap
./setup-all.sh
# Logout and login

# 4. Continue setup
./setup-services.sh

# 5. Setup Cloudflare Tunnel
# Get token from Cloudflare dashboard, add to .env
./scripts/07-setup-cloudflare-tunnel.sh

# 6. Setup ad blocker (optional)
# Add Pi-hole password to .env
./scripts/20-setup-adblocker.sh

# 7. Setup disaster recovery (optional)
# Get GitLab Cloud token, add to .env
./scripts/19-setup-complete-dr.sh

# 8. Verify
./scripts/08-health-check.sh
```

See [SETUP-PATH-A.md](SETUP-PATH-A.md) for detailed steps.

### Path B: Fresh Flash from laptop

**NVMe enclosure is required.**

```bash
# 1. On laptop
git clone <this-repo> pi-at-home-bootstrap
cd pi-at-home-bootstrap
cp env.example .env
vim .env  # Fill in all variables

# 2. Flash NVMe (connected via USB and an NVMe closure)
./scripts/00-flash-nvme.sh

# 3. Install NVMe in Pi and boot
# Wait 5-10 minutes for cloud-init

# 4. SSH into Pi
ssh username@hostname
cd pi-at-home-bootstrap
./setup-all.sh
# Logout and login

# 5. Continue setup
./setup-services.sh
./scripts/07-setup-cloudflare-tunnel.sh

# 6. Setup ad blocker (optional)
./scripts/20-setup-adblocker.sh

# 7. Setup disaster recovery (optional)
./scripts/19-setup-complete-dr.sh

# 8. Verify
./scripts/08-health-check.sh
```

See [SETUP-PATH-B.md](SETUP-PATH-B.md) for detailed steps.

---

## Configuration

Required in .env
```.env
HOSTNAME=gitlab
DOMAIN=yourdomain.com
USERNAME=spreadsheet-hater
EMAIL=spreadsheet-hater@yourdomain.com
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3..."
GITLAB_ROOT_PASSWORD=supersecret
GRAFANA_ADMIN_PASSWORD=supersecret
TIMEZONE=UTC
CLOUDFLARE_ACCOUNT_ID=your_account_id
CLOUDFLARE_TUNNEL_TOKEN=xxx

# Optional features
PIHOLE_WEB_PASSWORD=change_this_secure_password
GITLAB_CLOUD_TOKEN=your_gitlab_cloud_token
DR_WEBHOOK_URL=https://your-webhook-url.com

# Cloud Provider Selection
USE_GCP=true  # Use GCP instead of AWS (better Always Free Tier)

# GCP Configuration (if USE_GCP=true)
GCP_PROJECT_ID=
GOOGLE_APPLICATION_CREDENTIALS=/path/to/gcp-key.json

# AWS Configuration (if USE_GCP=false)
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=

# Cloud Backup (works with both GCP and AWS)
BACKUP_BUCKET=  # Format: gs://bucket-name (GCP) or s3://bucket-name (AWS)
```

---

## What to Expect

- GitLab CE at `https://gitlab.yourdomain.com`
- Container Registry at `https://registry.yourdomain.com`
- Grafana at `https://grafana.yourdomain.com`
- Pi-hole at `https://pihole.yourdomain.com`
- GitLab Runner for CI/CD
- Daily automated backups (local + GCP/AWS)
- GitLab Cloud mirroring for disaster recovery
- Prometheus monitoring
- Full security hardening
- No exposed ports (Cloudflare Tunnel only)

---

## Ad Blocker (Pi-hole)

### Network-wide Ad Blocking
- **Pi-hole**: Industry-standard DNS-based ad blocker
- **Unbound**: Local recursive DNS resolver for privacy
- **Network-wide**: All devices benefit automatically
- **Web interface**: Easy management and monitoring
- **Cloudflare integration**: Accessible via tunnel

### Features
- **DNS filtering**: Blocks ads at DNS level
- **Privacy protection**: No external DNS queries
- **Performance**: DNS caching improves speed
- **Customization**: Whitelist/blacklist management
- **Statistics**: Detailed query and blocking stats

### Access Points
- **Local**: `http://pi-ip:8080/admin`
- **External**: `https://pihole.yourdomain.com/admin`
- **Password**: Set in `.env` as `PIHOLE_WEB_PASSWORD`

### Configuration
```bash
# Setup ad blocker
./scripts/20-setup-adblocker.sh

# Configure network
/srv/pihole/configure-network.sh

# Check status
/srv/pihole/monitor.sh
```

### Network Setup
1. **Router DNS**: Set to Pi IP address
2. **Device DNS**: Configure individual devices
3. **Test**: `nslookup doubleclick.net pi-ip`

---

## Disaster Recovery

The disaster recovery that nobody asks for... but why not?

### GitLab Cloud Mirroring
- **Automatic mirroring**: All repositories synced to GitLab Cloud
- **Real-time updates**: Webhook-triggered mirroring on push/merge
- **Health monitoring**: Prometheus metrics-based health checks (webhook-triggered)
- **Failover**: Automatic DR activation when Pi goes down
- **Recovery**: Automated sync back to Pi when restored

### DR Components
- **Mirror Group**: `https://gitlab.com/groups/yourhostname-mirror`
- **Health Monitor**: Prometheus alerts trigger DR actions
- **Status Server**: `http://pi-ip:8081/status`
- **Webhook Handler**: `http://pi-ip:8081/webhook`

### DR Commands
```bash
# Check DR status
curl http://localhost:8081/status

# Test DR system
/srv/gitlab-dr/test-dr.sh

# Manual mirror sync
/srv/gitlab-mirror/mirror-repos.sh

# Force recovery from cloud
/srv/gitlab-dr/recover-from-cloud.sh

# View DR logs
tail -f /srv/gitlab-dr/dr.log
```

### DR Configuration
Add to `.env`:
```bash
GITLAB_CLOUD_TOKEN=your_gitlab_cloud_token
DR_WEBHOOK_URL=https://your-webhook-url.com
```

---

## Maintenance

### Common Commands

```bash
# Pre-flight check (before setup)
./scripts/00-preflight-check.sh

# Health check
./scripts/08-health-check.sh

# Update services
./scripts/09-update-services.sh

# Performance benchmark
./scripts/10-benchmark.sh

# Network diagnostics
./scripts/11-network-diag.sh

# Scale resources (adjust workers/memory)
./scripts/12-scale-resources.sh

# Setup Git LFS
./scripts/13-setup-lfs.sh

# Add additional runner
./scripts/14-add-runner.sh

# Import Grafana dashboards
./scripts/15-import-dashboards.sh

# Manual backup
./backup/backup.sh

# Restore from backup
./backup/restore.sh gitlab-backup-YYYYMMDD_HHMMSS

# View logs
docker compose -f compose/gitlab.yml logs -f gitlab
docker compose -f compose/monitoring.yml logs -f grafana
docker compose -f compose/adblocker.yml logs -f pihole

# Restart services
cd compose
docker compose -f compose/gitlab.yml restart
docker compose -f monitoring.yml restart
docker compose -f adblocker.yml restart

# Check Pi-hole status
/srv/pihole/monitor.sh

# Check DR status
curl http://localhost:8081/status

# Check temperature
/usr/local/bin/check-temp

# Firewall status
sudo ufw status

# Tunnel status
sudo systemctl status cloudflared

# Full cleanup (removes everything)
./scripts/99-cleanup.sh
```

---

## Updating the System

Keep things current:
```bash
sudo apt update && sudo apt full-upgrade -y
docker compose -f compose/gitlab.yml pull
docker compose -f compose/monitoring.yml pull
docker compose -f compose/adblocker.yml pull
./scripts/09-update-services.sh
```

---

## Resource Tuning

GitLab is configured for Pi 5 with conservative settings in `config/gitlab.rb.template`:
- Puma: 2 workers, 2 threads
- Sidekiq: 10 concurrency
- PostgreSQL: 256MB shared buffers

**Quick scaling:**
```bash
./scripts/12-scale-resources.sh
```

Profiles: Light (4GB), Medium (8GB), Heavy (8GB+), or Custom.

---

## Troubleshooting

### Common Issues

#### GitLab won't start
```bash
docker logs gitlab
sudo dmesg | grep oom
```
Check memory usage. GitLab needs at least 4GB total RAM (including swap).

#### Services can't communicate
```bash
docker network ls
docker network inspect gitlab-network
```

#### Cloudflare Tunnel not connecting
```bash
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f
```

#### High temperature
```bash
/usr/local/bin/check-temp
vcgencmd measure_temp
```
Ensure proper cooling.

#### Out of disk
```bash
ncdu /srv
```
Clean up old backups or logs.

---

## Monitoring & Alerts

**Grafana Dashboards:**
- GitLab metrics (requests, memory, CI/CD jobs)
- System metrics (CPU, RAM, disk, temperature, network)
- Log analysis (Loki integration)

**Prometheus Alerts:**
- System: High CPU/memory, low disk, high temperature
- GitLab: Service down, high memory usage
- Docker: Container failures

**Log Aggregation:**
- Loki: Centralized log storage
- Alloy: Log collection agent
- Integration with Grafana for log analysis

Import dashboards: `./scripts/15-import-dashboards.sh`

View alerts: http://localhost:9090/alerts
View logs: http://localhost:3000/explore (Loki datasource)

---

## Security Notes

- SSH password authentication is disabled
- Root login is disabled
- UFW blocks all incoming except SSH
- fail2ban monitors SSH and GitLab
- Automatic security updates enabled
- No ports exposed to internet (Cloudflare Tunnel only)

---

## Migration from GitHub

1. In GitLab, go to Projects > New Project > Import Project > GitHub
2. Follow the import wizard
3. Convert GitHub Actions to `.gitlab-ci.yml`

Check the `examples/` directory for ready-to-use CI/CD templates:
- `gitlab-ci-docker.yml` - Docker build and push
- `gitlab-ci-nodejs.yml` - Node.js projects
- `gitlab-ci-python.yml` - Python projects

See [examples/README.md](examples/README.md) for details.

---

## License

MIT
