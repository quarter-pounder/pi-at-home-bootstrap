#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

echo "[i] Setting up webhook-based disaster recovery automation..."

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

# Create webhook receiver service
echo "[i] Creating webhook receiver service..."
sudo tee /etc/systemd/system/prometheus-webhook-receiver.service >/dev/null <<EOF
[Unit]
Description=Prometheus Webhook Receiver for DR
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/srv/gitlab-dr
Environment=DR_WEBHOOK_URL=${DR_WEBHOOK_URL}
Environment=WEBHOOK_PORT=9093
ExecStart=/usr/bin/python3 /srv/gitlab-dr/prometheus-webhook-receiver.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Copy webhook receiver script
echo "[i] Installing webhook receiver..."
cp scripts/prometheus-webhook-receiver.py /srv/gitlab-dr/
chmod +x /srv/gitlab-dr/prometheus-webhook-receiver.py

# Install Python requests if not available
if ! python3 -c "import requests" 2>/dev/null; then
  echo "[i] Installing Python requests library..."
  sudo apt update
  sudo apt install -y python3-requests
fi

# Create DR recovery script (simplified version)
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

# Start services
echo "[i] Starting DR services..."
sudo systemctl enable prometheus-webhook-receiver
sudo systemctl start prometheus-webhook-receiver
sudo systemctl enable gitlab-dr-status
sudo systemctl start gitlab-dr-status

# Create Alertmanager directory
echo "[i] Creating Alertmanager directory..."
sudo mkdir -p /srv/alertmanager
sudo chown -R 65534:65534 /srv/alertmanager

# Update .env with DR webhook URL
if ! grep -q "DR_WEBHOOK_URL=" .env; then
  echo "DR_WEBHOOK_URL=" >> .env
fi

echo ""
echo "Webhook-based disaster recovery automation setup complete!"
echo ""
echo "Services:"
echo "  Webhook receiver: sudo systemctl status prometheus-webhook-receiver"
echo "  Status server: sudo systemctl status gitlab-dr-status"
echo "  Alertmanager: http://localhost:9093"
echo ""
echo "Endpoints:"
echo "  Status: http://$(hostname -I | awk '{print $1}'):8081/status"
echo "  Webhook: http://$(hostname -I | awk '{print $1}'):8081/webhook"
echo "  Prometheus alerts: http://localhost:9090/alerts"
echo ""
echo "DR is now triggered by Prometheus metrics instead of polling!"
echo "Alerts will automatically trigger DR activation/recovery."
