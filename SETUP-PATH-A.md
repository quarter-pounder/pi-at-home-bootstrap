# Setup Path A: Already Running on SD Card

## Prerequisites
- Pi 5 running Ubuntu Server (on SD card)
- NVMe drive attached to Pi
- SSH access to Pi
- Git installed on Pi

## Steps

### 1. Clone Repository on Pi

```bash
ssh username@pi-ip
sudo apt update && sudo apt install -y git
git clone <repo-url> gitlab-bootstrap
cd gitlab-bootstrap
```

### 2. Configure Environment

```bash
cp env.example .env
vim .env
```

Fill in all variables. Most importantly:
- `HOSTNAME`, `DOMAIN`, `USERNAME`, `EMAIL`
- `SSH_PUBLIC_KEY` (your public key)
- `GITLAB_ROOT_PASSWORD`
- `GRAFANA_ADMIN_PASSWORD`

### 3. Migrate to NVMe

```bash
./scripts/00-migrate-to-nvme.sh
```

This will:
- Detect NVMe drive
- Partition and format it
- Copy entire SD card contents to NVMe
- Update boot configuration
- Prompt for poweroff

After poweroff:
1. Remove SD card
2. Power on Pi (boots from NVMe)
3. SSH back in

### 4. Verify NVMe Boot

```bash
lsblk
df -h
```

Root should mount from `/dev/nvme0n1p2`

### 5. Run Setup Scripts

```bash
cd gitlab-bootstrap
./setup-all.sh
```

Follow prompts. After Docker install, logout and login again.

```bash
./setup-services.sh
```

This installs GitLab, Runner, and Monitoring.

### 6. Setup Cloudflare Tunnel

Create tunnel in Cloudflare dashboard, get token, add to `.env`

```bash
./scripts/07-setup-cloudflare-tunnel.sh
```

### 7. Verify Everything

```bash
./scripts/08-health-check.sh
```

Done. Access GitLab at `https://gitlab.yourdomain.com`

