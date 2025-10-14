# Setup Path B: Fresh Flash from Workstation

## Prerequisites
- Laptop/Workstation (macOS or Linux)
- NVMe drive (can connect via USB adapter)
- Pi 5 (can be brand new, no SD card needed)

## Steps

### 1. Configure on Workstation

```bash
git clone <repo-url> gitlab-bootstrap
cd gitlab-bootstrap
cp env.example .env
vim .env
```

Fill in all variables, especially:
- `HOSTNAME`, `DOMAIN`, `USERNAME`, `EMAIL`
- `SSH_KEY` (your public key)
- `GITLAB_ROOT_PASSWORD`
- `GRAFANA_ADMIN_PASSWORD`

### 2. Flash NVMe from Workstation

Connect NVMe to workstation via USB adapter.

```bash
./scripts/00-flash-nvme.sh
```

This will:
- Download Ubuntu Server ARM64
- Flash to NVMe
- Inject cloud-init configuration
- Configure user, SSH, firewall, swap

### 3. First Boot

1. Remove NVMe from workstation
2. Install in Pi 5
3. Power on Pi
4. Wait 5-10 minutes for cloud-init to complete
5. SSH in: `ssh username@hostname`

### 4. Clone Repo on Pi

```bash
git clone <repo-url> gitlab-bootstrap
cd gitlab-bootstrap
cp /path/to/.env .env  # Copy .env from workstation or recreate it
```

### 5. Run Setup Scripts

```bash
./setup-all.sh
```

Logout and login after Docker install.

```bash
./setup-services.sh
```

### 6. Setup Cloudflare Tunnel

Create tunnel in Cloudflare dashboard, get token, add to `.env`

```bash
./scripts/07-setup-cloudflare-tunnel.sh
```

### 7. Verify

```bash
./scripts/08-health-check.sh
```

Done. Access GitLab at `https://gitlab.yourdomain.com`

