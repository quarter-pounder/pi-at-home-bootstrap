#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

echo "[i] Setting up disaster recovery automation..."

# Check if webhook URL is provided
if [[ -z "${DR_WEBHOOK_URL:-}" ]]; then
  echo "[!] DR_WEBHOOK_URL not set in .env"
  echo ""
  echo "Set up a webhook URL for DR notifications:"
  echo "  - Use a service like ngrok for testing"
  echo "  - Or use a cloud function (AWS Lambda, etc.)"
  echo "  - Add to .env: DR_WEBHOOK_URL=https://your-webhook-url.com"
  exit 1
fi

# Create DR automation directory
echo "[i] Creating DR automation directory..."
mkdir -p /srv/gitlab-dr

# Create DR status checker
echo "[i] Creating DR status checker..."
cat > /srv/gitlab-dr/check-pi-status.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/srv/gitlab-mirror/config.json"
DR_DIR="/srv/gitlab-dr"
LOG_FILE="${DR_DIR}/dr.log"

# Load configuration
GITLAB_CLOUD_TOKEN=$(jq -r '.gitlab_cloud_token' "$CONFIG_FILE")
MIRROR_GROUP_ID=$(jq -r '.mirror_group_id' "$CONFIG_FILE")
HOSTNAME=$(jq -r '.hostname' "$CONFIG_FILE")

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if Pi services are healthy
check_pi_health() {
  local services=("gitlab" "prometheus" "grafana" "loki")
  local healthy=true

  for service in "${services[@]}"; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
      log "Service $service is not running"
      healthy=false
    fi
  done

  if ! curl -sf http://localhost/-/health >/dev/null 2>&1; then
    log "GitLab health check failed"
    healthy=false
  fi

  echo "$healthy"
}

# Send DR notification
send_dr_notification() {
  local status="$1"
  local message="$2"

  curl -s -X POST "$DR_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"status\": \"$status\",
      \"message\": \"$message\",
      \"hostname\": \"$HOSTNAME\",
      \"timestamp\": \"$(date -Iseconds)\"
    }" || log "Failed to send DR notification"
}

# Check GitLab Cloud mirror status
check_mirror_status() {
  local project_count
  project_count=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_CLOUD_TOKEN}" \
    "https://gitlab.com/api/v4/groups/${MIRROR_GROUP_ID}/projects" | \
    jq '. | length')

  echo "$project_count"
}

# Main health check
main() {
  log "Starting Pi health check"

  if check_pi_health; then
    log "Pi is healthy"
    echo "healthy" > "${DR_DIR}/status"

    # Check if we were in DR mode and recovered
    if [[ -f "${DR_DIR}/dr-active" ]]; then
      log "Pi recovered from DR mode"
      send_dr_notification "recovered" "Pi GitLab is back online"
      rm -f "${DR_DIR}/dr-active"
    fi
  else
    log "Pi is unhealthy"
    echo "unhealthy" > "${DR_DIR}/status"

    # Check if we should activate DR
    if [[ ! -f "${DR_DIR}/dr-active" ]]; then
      local mirror_count
      mirror_count=$(check_mirror_status)

      if [[ "$mirror_count" -gt 0 ]]; then
        log "Activating DR mode - $mirror_count projects available on GitLab Cloud"
        echo "$(date -Iseconds)" > "${DR_DIR}/dr-active"
        send_dr_notification "dr-activated" "Pi GitLab is down, using GitLab Cloud mirror"
      else
        log "No mirrors available for DR"
        send_dr_notification "dr-failed" "Pi GitLab is down but no mirrors available"
      fi
    fi
  fi
}

main "$@"
EOF

chmod +x /srv/gitlab-dr/check-pi-status.sh

# Create DR recovery script
echo "[i] Creating DR recovery script..."
cat > /srv/gitlab-dr/recover-from-cloud.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/srv/gitlab-mirror/config.json"
DR_DIR="/srv/gitlab-dr"
LOG_FILE="${DR_DIR}/recovery.log"

# Load configuration
GITLAB_CLOUD_TOKEN=$(jq -r '.gitlab_cloud_token' "$CONFIG_FILE")
MIRROR_GROUP_ID=$(jq -r '.mirror_group_id' "$CONFIG_FILE")
PI_GITLAB_URL=$(jq -r '.pi_gitlab_url' "$CONFIG_FILE")
PI_GITLAB_TOKEN=$(jq -r '.pi_gitlab_token' "$CONFIG_FILE")

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Sync repositories from GitLab Cloud back to Pi
sync_from_cloud() {
  log "Starting sync from GitLab Cloud"

  # Get all projects from mirror group
  local projects
  projects=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_CLOUD_TOKEN}" \
    "https://gitlab.com/api/v4/groups/${MIRROR_GROUP_ID}/projects" | \
    jq -r '.[] | "\(.id)|\(.name)|\(.path_with_namespace)"')

  if [[ -z "$projects" ]]; then
    log "No projects found in mirror group"
    return 0
  fi

  echo "$projects" | while IFS='|' read -r project_id project_name project_path; do
    log "Syncing project: $project_path"

    # Clone from GitLab Cloud
    local temp_dir="/tmp/gitlab-sync-${project_name}"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    git clone "https://oauth2:${GITLAB_CLOUD_TOKEN}@gitlab.com/${project_path}.git" "$temp_dir"

    # Push to Pi GitLab
    cd "$temp_dir"
    git remote add pi "${PI_GITLAB_URL}/${project_path}.git"
    git push pi --all
    git push pi --tags

    # Cleanup
    cd /
    rm -rf "$temp_dir"

    log "Synced project: $project_path"
  done

  log "Sync from GitLab Cloud completed"
}

# Main recovery process
main() {
  log "Starting recovery from GitLab Cloud"

  # Wait for Pi GitLab to be ready
  log "Waiting for Pi GitLab to be ready..."
  for i in {1..30}; do
    if curl -sf "${PI_GITLAB_URL}/-/health" >/dev/null 2>&1; then
      log "Pi GitLab is ready"
      break
    fi
    log "Still waiting... ($i/30)"
    sleep 10
  done

  # Sync repositories
  sync_from_cloud

  # Clear DR status
  rm -f "${DR_DIR}/dr-active"
  echo "recovered" > "${DR_DIR}/status"

  log "Recovery completed"
}

main "$@"
EOF

chmod +x /srv/gitlab-dr/recover-from-cloud.sh

# Create systemd service for health monitoring
echo "[i] Creating health monitoring service..."
sudo tee /etc/systemd/system/gitlab-dr-monitor.service >/dev/null <<EOF
[Unit]
Description=GitLab DR Health Monitor
After=network.target docker.service

[Service]
Type=oneshot
User=root
WorkingDirectory=/srv/gitlab-dr
ExecStart=/srv/gitlab-dr/check-pi-status.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create systemd timer for periodic health checks
echo "[i] Creating health monitoring timer..."
sudo tee /etc/systemd/system/gitlab-dr-monitor.timer >/dev/null <<EOF
[Unit]
Description=GitLab DR Health Monitor Timer
Requires=gitlab-dr-monitor.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=2min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer
echo "[i] Starting health monitoring..."
sudo systemctl enable gitlab-dr-monitor.timer
sudo systemctl start gitlab-dr-monitor.timer

# Create DR status endpoint
echo "[i] Creating DR status endpoint..."
cat > /srv/gitlab-dr/status-server.py <<'EOF'
#!/usr/bin/env python3
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

class DRStatusHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            status_file = '/srv/gitlab-dr/status'
            if os.path.exists(status_file):
                with open(status_file, 'r') as f:
                    status = f.read().strip()
            else:
                status = 'unknown'

            response = {
                'status': status,
                'dr_active': os.path.exists('/srv/gitlab-dr/dr-active'),
                'timestamp': os.popen('date -Iseconds').read().strip()
            }

            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/webhook':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)

            # Log webhook data
            with open('/srv/gitlab-dr/webhook.log', 'a') as f:
                f.write(f"{os.popen('date -Iseconds').read().strip()}: {post_data.decode()}\n")

            self.send_response(200)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), DRStatusHandler)
    server.serve_forever()
EOF

chmod +x /srv/gitlab-dr/status-server.py

# Create systemd service for status server
echo "[i] Creating status server service..."
sudo tee /etc/systemd/system/gitlab-dr-status.service >/dev/null <<EOF
[Unit]
Description=GitLab DR Status Server
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/srv/gitlab-dr
ExecStart=/usr/bin/python3 /srv/gitlab-dr/status-server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start status server
echo "[i] Starting status server..."
sudo systemctl enable gitlab-dr-status
sudo systemctl start gitlab-dr-status

# Update .env with DR webhook URL
if ! grep -q "DR_WEBHOOK_URL=" .env; then
  echo "DR_WEBHOOK_URL=" >> .env
fi

echo ""
echo "Disaster recovery automation setup complete!"
echo ""
echo "Services:"
echo "  Health monitor: sudo systemctl status gitlab-dr-monitor.timer"
echo "  Status server: sudo systemctl status gitlab-dr-status"
echo ""
echo "Endpoints:"
echo "  Status: http://$(hostname -I | awk '{print $1}'):8080/status"
echo "  Webhook: http://$(hostname -I | awk '{print $1}'):8080/webhook"
echo ""
echo "Manual commands:"
echo "  Check status: /srv/gitlab-dr/check-pi-status.sh"
echo "  Recover from cloud: /srv/gitlab-dr/recover-from-cloud.sh"
echo ""
echo "Logs:"
echo "  DR logs: /srv/gitlab-dr/dr.log"
echo "  Recovery logs: /srv/gitlab-dr/recovery.log"
echo "  Webhook logs: /srv/gitlab-dr/webhook.log"
