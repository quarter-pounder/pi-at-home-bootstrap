# Implemented Feature List

## Installation Options

- **Path A**: SD card to NVMe migration (while system running)
- **Path B**: Fresh NVMe flash from workstation with cloud-init

## Core Services

- **GitLab CE** - Self-hosted Git repository and CI/CD platform
- **GitLab Runner** - CI/CD job executor with Docker support
- **Container Registry** - Private Docker image storage
- **Prometheus** - Metrics collection and alerting
- **Grafana** - Visualization dashboards
- **Node Exporter** - System metrics (CPU, RAM, disk, network)
- **cAdvisor** - Container metrics
- **Cloudflare Tunnel** - Secure remote access without port forwarding

## Security Features

- SSH hardening (no password, no root, key-only)
- UFW firewall (deny all incoming except SSH)
- fail2ban (SSH + GitLab brute-force protection)
- Automatic security updates
- Kernel hardening (sysctl)
- No exposed ports (Cloudflare Tunnel only)

## Monitoring & Alerting

### Grafana Dashboards
- GitLab metrics (HTTP requests, memory, CI/CD jobs, health)
- System metrics (CPU, RAM, disk, temperature, network)

### Prometheus Alerts
- High CPU usage (>80%)
- High memory usage (>85%)
- Low disk space (>85%, critical >95%)
- High temperature (>80°C, critical >85°C)
- GitLab service down
- Runner offline
- Container failures

## Backup & Recovery

- Automated daily backups (cron)
- Local storage + optional S3 sync
- Configurable retention policies
- Complete restore scripts
- Includes GitLab data, config, runners, registry

## Performance Optimization

- Resource profiles (Light/Medium/Heavy/Custom)
- Tuned for Raspberry Pi 5 (ARM64)
- 2GB swap with low swappiness
- Docker log rotation (10MB x 3 files)
- PostgreSQL optimization
- Temperature monitoring

## Operational Tools

### Setup & Validation
- Pre-flight checks (OS, RAM, disk, internet, .env)
- One-liner installer
- Automated setup scripts
- Health checks

### Maintenance
- Update management (GitLab, monitoring, system)
- Performance benchmarking
- Network diagnostics
- Resource scaling
- Clean uninstall

### Advanced Features
- Git LFS support
- Multi-runner setup
- Custom CI/CD templates (Docker, Node.js, Python)
- Dashboard import automation

## CI/CD Features

- Docker-in-Docker support
- Private registry integration
- Parallel job execution (multi-runner)
- Artifact storage
- Code coverage reports
- Pipeline caching

## Example Templates

- Docker build and push workflow
- Node.js with caching and coverage
- Python with pytest and linting
- Complete usage documentation

## Resource Requirements

**Minimum:**
- Raspberry Pi 5 (4GB RAM)
- 32GB storage
- Internet connection

**Recommended(aka, my setup):**
- Raspberry Pi 5 (8GB RAM)
- 128GB+ NVMe drive
- Active cooling
- Domain with Cloudflare

## Automation Level

**Fully automated:**
- OS flashing and initial setup
- Service deployment
- Security hardening
- Backup scheduling
- Alert configuration

**One command:**
- Health checks
- Updates
- Benchmarking
- Network diagnostics
- Resource scaling

**Minimal configuration required:**
- Just .env
- Cloudflare Tunnel token
- GitLab runner token
