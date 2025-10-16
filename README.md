# GitLab on Raspberry Pi 5 - Bootstrap

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Platform: Raspberry Pi 5](https://img.shields.io/badge/Platform-Raspberry%20Pi%205-orange)
![Ubuntu: 24.04 LTS](https://img.shields.io/badge/Ubuntu-24.04%20LTS-purple)
![Status: Stable](https://img.shields.io/badge/Status-Stable-brightgreen)

My own setup for running GitLab CE with CI/CD runners, monitoring, and Cloudflare Tunnel on Raspberry Pi 5 with Ubuntu.
Or, we have GitLab at home.

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
- Automated backup to S3 or local storage
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

> **Note:** All scripts assume you’re running from the project root directory.
> To be safe:
> ```bash
> cd ~/gitlab-bootstrap
> ```

---

## Quick Start

Choose a setup path:

### Path A: Already Running Ubuntu on SD Card (My case)

```bash
# 1. On Pi (running from SD card)
git clone <this-repo> gitlab-bootstrap
cd gitlab-bootstrap
cp env.example .env
vim .env  # Fill in all variables

# Optional: Run pre-flight checks
./scripts/00-preflight-check.sh

# 2. Migrate to NVMe
./scripts/00-migrate-to-nvme.sh
# Poweroff, remove SD card, boot from NVMe

# 3. After booting from NVMe
cd gitlab-bootstrap
./setup-all.sh
# Logout and login

# 4. Continue setup
./setup-services.sh

# 5. Setup Cloudflare Tunnel
# Get token from Cloudflare dashboard, add to .env
./scripts/07-setup-cloudflare-tunnel.sh

# 6. Setup disaster recovery (optional)
# Get GitLab Cloud token, add to .env
./scripts/19-setup-complete-dr.sh

# 7. Verify
./scripts/08-health-check.sh
```

See [SETUP-PATH-A.md](SETUP-PATH-A.md) for detailed steps.

### Path B: Fresh Flash from laptop

NVMe enclosure is required.

```bash
# 1. On laptop
git clone <this-repo> gitlab-bootstrap
cd gitlab-bootstrap
cp env.example .env
vim .env  # Fill in all variables

# 2. Flash NVMe (connected via USB and an NVMe closure)
./scripts/00-flash-nvme.sh

# 3. Install NVMe in Pi and boot
# Wait 5-10 minutes for cloud-init

# 4. SSH into Pi
ssh username@hostname
cd gitlab-bootstrap
./setup-all.sh
# Logout and login

# 5. Continue setup
./setup-services.sh
./scripts/07-setup-cloudflare-tunnel.sh

# 6. Setup disaster recovery (optional)
./scripts/19-setup-complete-dr.sh

# 7. Verify
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
SSH_KEY="ssh-ed25519 AAAAC3..."
GITLAB_ROOT_PASSWORD=supersecret
GRAFANA_ADMIN_PASSWORD=supersecret
CLOUDFLARE_TUNNEL_TOKEN=xxx

# Optional backups
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
BACKUP_BUCKET=
```

---

## What You Get

- GitLab CE at `https://gitlab.yourdomain.com`
- Container Registry at `https://registry.yourdomain.com`
- Grafana at `https://grafana.yourdomain.com`
- GitLab Runner for CI/CD
- Daily automated backups (local + S3)
- GitLab Cloud mirroring for disaster recovery
- Prometheus monitoring
- Full security hardening
- No exposed ports (Cloudflare Tunnel only)

---

## Disaster Recovery

### GitLab Cloud Mirroring
- **Automatic mirroring**: All repositories synced to GitLab Cloud
- **Real-time updates**: Webhook-triggered mirroring on push/merge
- **Health monitoring**: Automated Pi health checks every 2 minutes
- **Failover**: Automatic DR activation when Pi goes down
- **Recovery**: Automated sync back to Pi when restored

### DR Components
- **Mirror Group**: `https://gitlab.com/groups/yourhostname-mirror`
- **Health Monitor**: Checks Pi services every 2 minutes
- **Status Server**: `http://pi-ip:8080/status`
- **Webhook Handler**: `http://pi-ip:8080/webhook`

### DR Commands
```bash
# Check DR status
curl http://localhost:8080/status

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

# Restart services
cd compose
docker compose -f gitlab.yml restart
docker compose -f monitoring.yml restart

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

**Prometheus Alerts:**
- System: High CPU/memory, low disk, high temperature
- GitLab: Service down, high memory usage
- Docker: Container failures

Import dashboards: `./scripts/15-import-dashboards.sh`

View alerts: http://localhost:9090/alerts

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

## Directory Structure

```
gitlab-bootstrap/
├── backup/              # Backup and restore scripts
├── cloudinit/           # Cloud-init templates (Path B only)
├── compose/             # Docker Compose files
├── config/              # Configuration files
│   ├── Dashboards (2) + Alerts + Service configs
│   └── README.md
├── examples/            # GitLab CI/CD example templates
│   ├── Docker, Node.js, Python workflows
│   └── README.md
├── scripts/             # Installation and setup scripts
│   ├── 00-preflight-check.sh      # Validate prerequisites
│   ├── 00-migrate-to-nvme.sh      # SD to NVMe migration
│   ├── 00-flash-nvme.sh           # Flash from workstation
│   ├── 01-08-*.sh                 # Setup and maintenance
│   ├── 09-update-services.sh      # Update management
│   ├── 10-benchmark.sh            # Performance testing
│   ├── 11-network-diag.sh         # Network diagnostics
│   ├── 12-scale-resources.sh      # Resource scaling
│   ├── 13-setup-lfs.sh            # Git LFS setup
│   ├── 14-add-runner.sh           # Multi-runner setup
│   ├── 15-import-dashboards.sh    # Dashboard import
│   └── 99-cleanup.sh              # Complete removal
├── env.example          # Environment variable template
├── install.sh           # One-liner installer
├── setup-all.sh         # Automated setup (part 1)
├── setup-services.sh    # Automated setup (part 2)
├── SETUP-PATH-A.md      # SD to NVMe guide
├── SETUP-PATH-B.md      # Fresh flash guide
├── SETUP-CHECKLIST.md   # Step-by-step checklist
├── FEATURES.md          # Complete feature list
├── IMPROVEMENTS.md      # Recent updates
├── MANIFEST.txt         # Complete inventory
└── README.md            # This file
```

---

## License

MIT
