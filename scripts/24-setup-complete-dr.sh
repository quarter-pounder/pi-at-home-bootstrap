#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

echo "[i] Setting up complete disaster recovery system..."

# Check prerequisites
echo "[i] Checking prerequisites..."

if [[ -z "${GITLAB_CLOUD_TOKEN:-}" ]]; then
  echo "[!] GITLAB_CLOUD_TOKEN not set in .env"
  echo "Please add your GitLab Cloud token to .env first"
  exit 1
fi

if [[ -z "${DR_WEBHOOK_URL:-}" ]]; then
  echo "[!] DR_WEBHOOK_URL not set in .env"
  echo "Please add your webhook URL to .env first"
  exit 1
fi

# Check if GitLab is running
if ! docker ps --format '{{.Names}}' | grep -q '^gitlab$'; then
  echo "[!] GitLab is not running. Start it first with: ./scripts/04-setup-gitlab.sh"
  exit 1
fi

# Step 1: Setup GitLab Cloud mirroring
echo ""
echo "Step 1: Setting up GitLab Cloud mirroring..."
./scripts/17-setup-gitlab-mirror.sh

# Step 2: Setup DR automation (webhook-based)
echo ""
echo "Step 2: Setting up DR automation..."
./scripts/18-setup-dr-webhook.sh

# Step 3: Create DR documentation
echo ""
echo "Step 3: Creating DR documentation..."
mkdir -p /srv/gitlab-dr/docs

cat > /srv/gitlab-dr/docs/DR_GUIDE.md <<EOF
# Disaster Recovery Guide

## Overview
This system provides automated disaster recovery for GitLab Pi using GitLab Cloud as a mirror.

## Architecture
- **Primary**: Pi GitLab (local)
- **Mirror**: GitLab Cloud (remote)
- **Monitoring**: Health checks every 2 minutes
- **Automation**: Webhook-triggered mirroring

## Components

### Mirroring System
- **Script**: \`/srv/gitlab-mirror/mirror-repos.sh\`
- **Service**: \`gitlab-mirror-webhook\`
- **Cron**: Every 6 hours
- **Config**: \`/srv/gitlab-mirror/config.json\`

### DR Monitoring
- **Prometheus Alerts**: Automatic DR triggers based on metrics
- **Alertmanager**: Routes alerts to webhook receiver
- **Webhook Receiver**: \`prometheus-webhook-receiver\`
- **Status Server**: \`gitlab-dr-status\`
- **Recovery**: \`/srv/gitlab-dr/recover-from-cloud.sh\`

## Status Monitoring

### Check Pi Status
\`\`\`bash
curl http://localhost:8081/status
\`\`\`

### Check DR Status
\`\`\`bash
sudo systemctl status prometheus-webhook-receiver
sudo systemctl status gitlab-dr-status
sudo systemctl status alertmanager
\`\`\`

### View Logs
\`\`\`bash
# DR logs
tail -f /srv/gitlab-dr/dr.log

# Mirror logs
tail -f /srv/gitlab-mirror/mirror.log

# Webhook logs
tail -f /srv/gitlab-dr/webhook.log
\`\`\`

## Manual Operations

### Force Mirror Sync
\`\`\`bash
/srv/gitlab-mirror/mirror-repos.sh
\`\`\`

### Check Prometheus Alerts
\`\`\`bash
curl http://localhost:9090/api/v1/alerts
curl http://localhost:9093/api/v1/alerts
\`\`\`

### Manual Recovery
\`\`\`bash
/srv/gitlab-dr/recover-from-cloud.sh
\`\`\`

## Webhook Configuration

### GitLab Pi Webhook
- **URL**: \`http://$(hostname -I | awk '{print $1}'):8081/webhook\`
- **Events**: Push events, Merge request events, Project events
- **Secret**: (optional)

### External Monitoring
- **Status URL**: \`http://$(hostname -I | awk '{print $1}'):8081/status\`
- **Webhook URL**: \`${DR_WEBHOOK_URL}\`

## Troubleshooting

### Mirror Not Working
1. Check GitLab Cloud token: \`jq -r '.gitlab_cloud_token' /srv/gitlab-mirror/config.json\`
2. Check mirror group: \`https://gitlab.com/groups/$(hostname)-mirror\`
3. Check logs: \`tail -f /srv/gitlab-mirror/mirror.log\`

### DR Not Activating
1. Check health monitor: \`sudo systemctl status gitlab-dr-monitor.timer\`
2. Check Pi status: \`/srv/gitlab-dr/check-pi-status.sh\`
3. Check webhook URL: \`echo \$DR_WEBHOOK_URL\`

### Recovery Issues
1. Check GitLab Cloud connectivity
2. Check Pi GitLab health
3. Check recovery logs: \`tail -f /srv/gitlab-dr/recovery.log\`

## Maintenance

### Update Mirror Group
Edit \`/srv/gitlab-mirror/config.json\` and restart services:
\`\`\`bash
sudo systemctl restart gitlab-mirror-webhook
\`\`\`

### Update DR Settings
Edit \`.env\` and restart services:
\`\`\`bash
sudo systemctl restart gitlab-dr-monitor.timer
sudo systemctl restart gitlab-dr-status
\`\`\`

### Cleanup Old Logs
\`\`\`bash
find /srv/gitlab-dr -name "*.log" -mtime +30 -delete
find /srv/gitlab-mirror -name "*.log" -mtime +30 -delete
\`\`\`
EOF

# Step 4: Create DR test script
echo ""
echo "Step 4: Creating DR test script..."
cat > /srv/gitlab-dr/test-dr.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Testing DR system..."

# Test 1: Check status endpoint
echo "Test 1: Status endpoint"
curl -s http://localhost:8080/status | jq '.'

# Test 2: Check mirror status
echo "Test 2: Mirror status"
if [[ -f /srv/gitlab-mirror/config.json ]]; then
  MIRROR_GROUP_ID=$(jq -r '.mirror_group_id' /srv/gitlab-mirror/config.json)
  GITLAB_CLOUD_TOKEN=$(jq -r '.gitlab_cloud_token' /srv/gitlab-mirror/config.json)

  PROJECT_COUNT=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_CLOUD_TOKEN}" \
    "https://gitlab.com/api/v4/groups/${MIRROR_GROUP_ID}/projects" | \
    jq '. | length')

  echo "Mirror group has $PROJECT_COUNT projects"
else
  echo "Mirror config not found"
fi

# Test 3: Check services
echo "Test 3: Service status"
echo "Health monitor: $(sudo systemctl is-active gitlab-dr-monitor.timer)"
echo "Status server: $(sudo systemctl is-active gitlab-dr-status)"
echo "Mirror webhook: $(sudo systemctl is-active gitlab-mirror-webhook)"

# Test 4: Manual health check
echo "Test 4: Manual health check"
/srv/gitlab-dr/check-pi-status.sh

echo "DR test completed"
EOF

chmod +x /srv/gitlab-dr/test-dr.sh

# Step 5: Update main setup scripts
echo ""
echo "Step 5: Updating main setup scripts..."

# Update setup-services.sh to include DR setup
if ! grep -q "17-setup-gitlab-mirror.sh" setup-services.sh; then
  sed -i '/step 7 "Setting up backups..."/a\\nstep 8 "Setting up GitLab Cloud mirroring..."\n./scripts/17-setup-gitlab-mirror.sh\n\nstep 9 "Setting up DR automation..."\n./scripts/18-setup-dr-webhook.sh' setup-services.sh
fi

# Update health check script
if ! grep -q "DR Status" scripts/21-health-check.sh; then
  sed -i '/echo "\[i\] Recent Backup:"/a\\necho ""\necho "\[i\] DR Status:"\nif curl -s http://localhost:8081/status >/dev/null 2>&1; then\n  echo "${GREEN}✓ DR system is responding${RESET}"\nelse\n  echo "${YELLOW}WARNING${RESET} DR system is not responding"\nfi' scripts/21-health-check.sh
fi

echo ""
echo "Complete disaster recovery system setup finished!"
echo ""
echo "Next steps:"
echo "  1. Test the system: /srv/gitlab-dr/test-dr.sh"
echo "  2. Configure webhooks in GitLab Pi"
echo "  3. Set up external monitoring"
echo ""
echo "Services created:"
echo "  - GitLab Cloud mirroring"
echo "  - DR health monitoring"
echo "  - Status server (port 8080)"
echo "  - Webhook handlers"
echo ""
echo "Disaster recovery is now set!"
