# Setup Checklist

## Pre-Flash (on workstation)
- [ ] Copy `env.example` to `.env`
- [ ] Fill in all required variables in `.env`
- [ ] Generate SSH key if needed: `ssh-keygen -t ed25519`
- [ ] Add SSH public key to `.env`
- [ ] Connect NVMe drive to workstation
- [ ] Run `./scripts/00-flash-nvme.sh`
- [ ] Install NVMe in Pi 5 and boot

## Post-Boot (on Pi)
- [ ] Wait 5-10 minutes for cloud-init to complete
- [ ] SSH into Pi: `ssh username@hostname`
- [ ] Clone repo: `git clone <repo-url>`
- [ ] Copy `.env` from workstation to Pi
- [ ] Run `./scripts/01-post-boot-setup.sh`
- [ ] Run `./scripts/02-security-hardening.sh`
- [ ] Run `./scripts/03-install-docker.sh`
- [ ] Logout and login again

## GitLab Setup
- [ ] Run `./scripts/04-setup-gitlab.sh`
- [ ] Wait 5-10 minutes for GitLab to start
- [ ] Access GitLab UI at `http://<pi-ip>`
- [ ] Login as `root` with password from `.env`
- [ ] Create new admin password if desired
- [ ] Create personal access token for API access
- [ ] Go to Admin > CI/CD > Runners
- [ ] Create new instance runner
- [ ] Copy runner token to `.env`
- [ ] Run `./scripts/05-register-runner.sh`
- [ ] Verify runner is online in GitLab UI

## Monitoring Setup
- [ ] Run `./scripts/06-setup-monitoring.sh`
- [ ] Access Grafana at `http://<pi-ip>:3000`
- [ ] Login with admin password from `.env`
- [ ] Import GitLab dashboard (ID: 10131)
- [ ] Import Node Exporter dashboard (ID: 1860)
- [ ] Import cAdvisor dashboard (ID: 14282)

## Cloudflare Tunnel
- [ ] Login to Cloudflare dashboard
- [ ] Go to Networks > Tunnels
- [ ] Create new tunnel with name from `.env`
- [ ] Copy tunnel token to `.env`
- [ ] Configure routes:
  - [ ] `gitlab.domain.com` → `http://localhost:80`
  - [ ] `registry.domain.com` → `http://localhost:5050`
  - [ ] `grafana.domain.com` → `http://localhost:3000`
- [ ] Run `./scripts/07-setup-cloudflare-tunnel.sh`
- [ ] Verify tunnel is connected in Cloudflare dashboard
- [ ] Test access to `https://gitlab.domain.com`

## Backup Configuration
- [ ] Configure S3 credentials in `.env` (optional)
- [ ] Run `./backup/setup-cron.sh` for automatic backups
- [ ] Run `./backup/backup.sh` to test backup manually
- [ ] Verify backup files in `${BACKUP_DIR}/gitlab/`
- [ ] If using S3, verify files in bucket

## Final Verification
- [ ] Run `./scripts/08-health-check.sh`
- [ ] All services show as healthy
- [ ] Create test project in GitLab
- [ ] Add `.gitlab-ci.yml` and verify runner picks up job
- [ ] Verify container registry works
- [ ] Check Grafana dashboards showing metrics
- [ ] Test external access via Cloudflare Tunnel
- [ ] Verify backups are running (check crontab)

## Optional Enhancements
- [ ] Configure SMTP for email notifications
- [ ] Enable GitLab Pages
- [ ] Configure LFS for large files
- [ ] Add more Grafana dashboards
- [ ] Configure alert rules in Prometheus
- [ ] Setup external monitoring/uptime check
- [ ] Document any custom CI/CD templates

## Notes
- Default GitLab SSH port: 2222
- Temperature monitoring runs every 5 minutes
- Backups run daily at 2 AM
- Keep `.env` file secure (never commit to git)

