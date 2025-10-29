# Recent Improvements

## Major New Features Added

### Log Aggregation Stack
**Services**: Loki + Alloy
- **Loki**: Centralized log storage and querying
- **Alloy**: Modern log collection agent (replaces Promtail)
- **Integration**: Grafana datasource for log analysis
- **Collection**: System logs, GitLab logs, Docker container logs
- **Configuration**: `config/loki.yml` and `config/alloy.river`

### Ad Blocker (Pi-hole)
**Service**: Pi-hole + Unbound
- **Pi-hole**: DNS-based ad blocking for entire network
- **Unbound**: Local recursive DNS resolver for privacy
- **Web Interface**: Management and statistics dashboard
- **Network-wide**: All devices benefit automatically
- **Cloudflare Integration**: Accessible via tunnel

### Disaster Recovery System
**Scripts**: 17-19
- **GitLab Cloud Mirroring**: Automatic repository sync
- **Health Monitoring**: Prometheus metrics-based health checks
- **Automated Failover**: DR activation when Pi goes down
- **Recovery Automation**: Sync back when Pi recovers
- **Webhook Integration**: External monitoring support

### Infrastructure as Code (Terraform)
**Directory**: `terraform/`
- **Cloudflare Module**: DNS records and tunnels
- **AWS Module**: S3 buckets, IAM, SNS alerts
- **Free Tier Optimized**: All resources within free limits
- **Automated Deployment**: One-command cloud setup

## New Features Added

### Pre-flight Validation
**Script**: `scripts/00-preflight-check.sh`
- Validates OS, architecture, memory, disk space
- Checks internet connectivity
- Verifies all required .env variables
- Confirms sudo access
- Run before setup to catch issues early

### Update Management
**Script**: `scripts/10-update-services.sh`
- Interactive update menu
- Update GitLab, monitoring, or system packages
- Automatic backup before GitLab updates
- Health check after updates

### Complete Cleanup
**Script**: `scripts/99-cleanup.sh`
- Remove all GitLab services and data
- Clean up Docker containers/volumes
- Remove Cloudflare tunnel
- Optional backup deletion
- Safe confirmation required

### CI/CD Templates
**Directory**: `examples/`
- Ready-to-use `.gitlab-ci.yml` templates
- Docker build and push workflow
- Node.js project with caching and coverage
- Python project with pytest and linting
- Complete documentation in examples/README.md

### One-liner Installer
**Script**: `install.sh`
- Quick clone and setup helper
- Can be used with curl | bash pattern
- Guides user through next steps

### Enhanced .gitignore
- Editor files (.idea, .vscode, swap files)
- Build artifacts and logs
- Backup directories
- Temporary files

## Usage Examples

### Before Setup
```bash
# Validate everything before starting
./scripts/00-preflight-check.sh
```

### Regular Maintenance
```bash
# Update everything (with backup)
./scripts/10-update-services.sh

# Just check system health
./scripts/21-health-check.sh
```

### Starting a New Project
```bash
# Copy appropriate CI template
cp examples/gitlab-ci-nodejs.yml ~/my-project/.gitlab-ci.yml

# Edit as needed
vim ~/my-project/.gitlab-ci.yml
```

### Complete Removal
```bash
# Remove everything if needed
./scripts/99-cleanup.sh
```

## Additional Nice-to-Haves Added

### Grafana Dashboards (Config Files)
**Files**: `config/grafana-dashboard-*.json`
- GitLab Overview dashboard (HTTP requests, memory, CI/CD jobs)
- Raspberry Pi System Metrics (CPU, RAM, disk, temp, network)
- Import with: `./scripts/15-import-dashboards.sh`

### Prometheus Alerts
**File**: `config/prometheus-alerts.yml`
- System alerts: High CPU/memory, low disk, temperature warnings
- GitLab alerts: Service down, high memory, runner failures
- Docker alerts: Container failures, high memory
- Auto-loaded by Prometheus, view at http://localhost:9090/alerts

### Performance Benchmark
**Script**: `scripts/10-benchmark.sh`
- CPU performance (sysbench)
- Memory throughput
- Disk I/O testing
- Docker container stats
- GitLab response time testing
- Temperature monitoring under load

### Network Diagnostics
**Script**: `scripts/11-network-diag.sh`
- Network interface status
- Internet connectivity tests
- DNS resolution checks
- Service endpoint validation
- Docker network inspection
- Cloudflare Tunnel status
- Firewall and port checks
- Download speed test

### Resource Scaler
**Script**: `scripts/13-scale-resources.sh`
- Interactive resource profile selection
- Light/Medium/Heavy/Custom profiles
- Adjusts Puma workers, Sidekiq concurrency
- PostgreSQL tuning
- Automatic GitLab restart

### Git LFS Setup
**Script**: `scripts/14-setup-lfs.sh`
- Enable Git Large File Storage in GitLab
- Configure storage paths
- Setup instructions for client use

### Multi-Runner Support
**Script**: `scripts/14-add-runner.sh`
- Add additional GitLab runners
- Support for parallel CI/CD jobs
- Docker or shell executor options
- Custom concurrency settings

### Dashboard Import Helper
**Script**: `scripts/15-import-dashboards.sh`
- Auto-import Grafana dashboards
- Wait for Grafana to be ready
- Batch import all dashboard JSONs

## Complete Feature List

Now includes:
- Pre-flight validation
- SD to NVMe migration
- Fresh flash from workstation
- Security hardening
- GitLab + Registry + Runners
- Prometheus + Grafana + Loki + Alloy
- Pi-hole ad blocker + Unbound DNS
- GitLab Cloud mirroring + DR automation
- Terraform infrastructure as code
- Automated backups (local + S3)
- Cloudflare Tunnel
- Health monitoring
- Update management
- Performance benchmarking
- Network diagnostics
- Resource scaling
- Git LFS support
- Multi-runner setup
- Pre-configured dashboards
- Alert rules
- Complete cleanup
- CI/CD templates
- One-liner installer
