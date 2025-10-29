# pi-forge Bootstrap

Minimal host setup for Raspberry Pi with Docker ready.

## Quick Start

```bash
# Clone and bootstrap
curl -sSL <raw-url-to-install.sh> | bash -s <repo-url>
cd pi-forge

# Configure environment
cp config-registry/env/base.env.example config-registry/env/base.env
vim config-registry/env/base.env

# Run bootstrap
bash bootstrap/00-preflight.sh
bash bootstrap/01-install-core.sh
bash bootstrap/02-install-docker.sh
bash bootstrap/03-verify.sh

# Logout and login to activate Docker group
```

## Bootstrap Scripts

- `install.sh` - Main installer script
- `00-preflight.sh` - System requirements check
- `01-install-core.sh` - Install core dependencies
- `02-install-docker.sh` - Install Docker and Docker Compose
- `03-verify.sh` - Verify installation
- `utils.sh` - Common utilities

## Requirements

- Ubuntu (ARM64)
- 4GB+ RAM (2GB minimum)
- 50GB+ disk space
- Internet connectivity
- Sudo access

## What Gets Installed

- Core tools: curl, wget, git, jq, yq, ansible
- Docker and Docker Compose
- Pi-specific tools: rpi-eeprom, nvme-cli
- Docker daemon configuration for Pi optimization
