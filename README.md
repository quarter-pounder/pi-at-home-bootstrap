# GitLab on Raspberry Pi 5 - Bootstrap

My own setup for running GitLab CE with CI/CD runners, monitoring, and Cloudflare Tunnel on Raspberry Pi 5 with Ubuntu.
Or, a proof that you don't need a $4000/month RHEL EC2 instance for a GitLab server.

## Prerequisites

- Raspberry Pi 5 (I went with 8GB)
- NVMe drive or high-quality SD card (NVMe works better in the long term, SD card wears out quickly)
- Domain name with Cloudflare DNS
- Cloudflare account (free tier should do the trick)

## Features

- Ubuntu Server ARM64 automated flash with cloud-init
- Docker and Docker Compose
- GitLab CE with container registry
- GitLab Runner with Docker executor
- Prometheus + Grafana monitoring stack
- Cloudflare Tunnel for secure remote access
- Automated backup to S3 or local storage
- Security hardening (UFW, fail2ban, SSH)
- Temperature and health monitoring

## Quick Start

Choose a setup path:

### Path A: Already Running Ubuntu on SD Card (My case)

```bash
# 1. On Pi (running from SD card)
git clone <this-repo> gitlab-bootstrap
cd gitlab-bootstrap
cp env.example .env
vim .env  # Fill in all variables

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

# 6. Verify
./scripts/08-health-check.sh
```

See [SETUP-PATH-A.md](SETUP-PATH-A.md) for detailed steps.

### Path B: Fresh Flash from laptop

```bash
# 1. On laptop
git clone <this-repo> gitlab-bootstrap
cd gitlab-bootstrap
cp env.example .env
vim .env  # Fill in all variables

# 2. Flash NVMe (connected via USB)
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
./scripts/08-health-check.sh
```

See [SETUP-PATH-B.md](SETUP-PATH-B.md) for detailed steps.

## What You Get

- GitLab CE at `https://gitlab.yourdomain.com`
- Container Registry at `https://registry.yourdomain.com`
- Grafana at `https://grafana.yourdomain.com`
- GitLab Runner for CI/CD
- Daily automated backups (local + S3)
- Prometheus monitoring
- Full security hardening
- No exposed ports (Cloudflare Tunnel only)

## Configuration

**Required in .env:**
- HOSTNAME, DOMAIN, USERNAME, EMAIL
- SSH_KEY
- GITLAB_ROOT_PASSWORD
- GRAFANA_ADMIN_PASSWORD
- CLOUDFLARE_TUNNEL_TOKEN (get after creating tunnel)

**Optional in .env:**
- AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, BACKUP_BUCKET

## Maintenance

### Common Commands

```bash
# Health check
./scripts/08-health-check.sh

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

# Update GitLab
docker compose -f gitlab.yml pull
docker compose -f gitlab.yml up -d

# Check temperature
/usr/local/bin/check-temp

# Firewall status
sudo ufw status

# Tunnel status
sudo systemctl status cloudflared
```

## Resource Tuning

GitLab is configured for Pi 5 with conservative settings in `config/gitlab.rb.template`:
- Puma: 2 workers, 2 threads
- Sidekiq: 10 concurrency
- PostgreSQL: 256MB shared buffers

For a 4GB Pi, consider reducing Sidekiq concurrency to 5.

## Troubleshooting

### GitLab won't start
```bash
docker logs gitlab
sudo dmesg | grep oom
```
Check memory usage. GitLab needs at least 4GB total RAM (including swap). What a beast.

### Services can't communicate
```bash
docker network ls
docker network inspect gitlab-network
```

### Cloudflare Tunnel not connecting
```bash
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -f
```

### High temperature
```bash
/usr/local/bin/check-temp
vcgencmd measure_temp
```
Ensure proper cooling. Pi 5 benefits from active cooling under load.

### Out of disk
```bash
ncdu /srv
```
Find large directories and clean up old backups or logs.

## Security Notes

- SSH password authentication is disabled
- Root login is disabled
- UFW blocks all incoming except SSH
- fail2ban monitors SSH and GitLab
- Automatic security updates enabled
- No ports exposed to internet (Cloudflare Tunnel only)

## Migration from GitHub

1. In GitLab, go to Projects > New Project > Import Project > GitHub
2. Follow the import wizard
3. Convert GitHub Actions to `.gitlab-ci.yml`:

GitHub Actions:
```yaml
name: Build
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - run: npm install
      - run: npm test
```

GitLab CI:
```yaml
stages:
  - build
  - test

build:
  stage: build
  script:
    - npm install

test:
  stage: test
  script:
    - npm test
```

## Directory Structure

```
gitlab-bootstrap/
├── backup/              # Backup and restore scripts
├── cloudinit/           # Cloud-init templates (Path B only)
├── compose/             # Docker Compose files
├── config/              # Configuration files
├── scripts/             # Installation and setup scripts
├── env.example          # Environment variable template
├── SETUP-PATH-A.md      # SD card to NVMe migration path
├── SETUP-PATH-B.md      # Fresh flash from workstation path
└── README.md            # This file
```

## License

MIT
