# GitLab on Raspberry Pi 5 - Bootstrap

A setup for running GitLab CE with CI/CD runners, monitoring, and Cloudflare Tunnel on Raspberry Pi 5 with Ubuntu.
Or, a proof that you don't need a $4000/month RHEL EC2 instance for a GitLab server.

## Prerequisites

- Raspberry Pi 5 (I went with 8GB)
- NVMe drive or high-quality SD card (NVMe works better in the long term)
- Domain name with Cloudflare DNS
- Cloudflare account (free tier should do)

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

If you can SSH into a Pi running Ubuntu on SD card:

1. SSH in and clone this repo
2. Configure `.env`
3. Run `./scripts/00-migrate-to-nvme.sh` to migrate to NVMe
4. Remove SD card, reboot from NVMe
5. Run `./setup-all.sh` then `./setup-services.sh`

See [SETUP-PATH-A.md](SETUP-PATH-A.md) for detailed steps.

### Path B: Fresh Flash from laptop

If you want to flash NVMe from your laptop or workstation with everything pre-configured:

1. Configure `.env`
2. Run `./scripts/00-flash-nvme.sh` with NVMe connected via USB
3. Install NVMe in Pi and boot (cloud-init does initial setup)
4. SSH in and run `./setup-all.sh` then `./setup-services.sh`

See [SETUP-PATH-B.md](SETUP-PATH-B.md) for detailed steps.

### Common Steps (Both Paths)

After initial setup, configure Cloudflare Tunnel:

```bash
./scripts/07-setup-cloudflare-tunnel.sh
```

Verify everything:

```bash
./scripts/08-health-check.sh
```

## Maintenance

### Health Check
```bash
./scripts/08-health-check.sh
```

### View Logs
```bash
docker compose -f compose/gitlab.yml logs -f gitlab
docker compose -f compose/monitoring.yml logs -f prometheus
```

### Restart Services
```bash
cd compose
docker compose -f gitlab.yml restart
docker compose -f monitoring.yml restart
```

### Update GitLab
```bash
cd compose
docker compose -f gitlab.yml pull
docker compose -f gitlab.yml up -d
```

### Restore from Backup
```bash
./backup/restore.sh gitlab-backup-YYYYMMDD_HHMMSS
```

## Resource Tuning

GitLab is configured for Pi 5 with conservative settings in `config/gitlab.rb.template`:
- Puma: 2 workers, 2 threads
- Sidekiq: 10 concurrency
- PostgreSQL: 256MB shared buffers

For 8GB Pi, you can increase these values. For 4GB Pi, consider reducing Sidekiq concurrency to 5.

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
```
Ensure proper cooling. Pi 5 benefits from active cooling under load.

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
