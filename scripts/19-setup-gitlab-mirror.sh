#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

echo "[i] Setting up GitLab Cloud mirroring..."

# Check if GitLab Cloud token is provided
if [[ -z "${GITLAB_CLOUD_TOKEN:-}" ]]; then
  echo "[!] GITLAB_CLOUD_TOKEN not set in .env"
  echo ""
  echo "Create a GitLab Cloud token:"
  echo "1. Go to https://gitlab.com/-/profile/personal_access_tokens"
  echo "2. Create token with 'api' scope"
  echo "3. Add to .env: GITLAB_CLOUD_TOKEN=your_token_here"
  exit 1
fi

# Check if GitLab is running
if ! docker ps --format '{{.Names}}' | grep -q '^gitlab$'; then
  echo "[!] GitLab is not running. Start it first with: ./scripts/04-setup-gitlab.sh"
  exit 1
fi

# Wait for GitLab to be ready
echo "[i] Waiting for GitLab to be ready..."
for i in {1..30}; do
  if curl -sfk https://localhost/-/health >/dev/null 2>&1; then
    echo "[i] GitLab is ready"
    break
  fi
  echo "[i] Still waiting... ($i/30)"
  sleep 10
done

# Create mirror group on GitLab Cloud
echo "[i] Creating mirror group on GitLab Cloud..."
MIRROR_GROUP_ID=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_CLOUD_TOKEN}" \
  --header "Content-Type: application/json" \
  --request POST \
  "https://gitlab.com/api/v4/groups" \
  --data "{
    \"name\": \"${HOSTNAME}-mirror\",
    \"path\": \"${HOSTNAME}-mirror\",
    \"description\": \"Mirror of ${HOSTNAME} GitLab repositories\",
    \"visibility\": \"private\"
  }" | jq -r '.id // empty')

if [[ -z "$MIRROR_GROUP_ID" ]]; then
  echo "[!] Failed to create mirror group. Check your token permissions."
  exit 1
fi

echo "[i] Mirror group created with ID: $MIRROR_GROUP_ID"

# Create mirror configuration
echo "[i] Creating mirror configuration..."
mkdir -p /srv/gitlab-mirror
cat > /srv/gitlab-mirror/config.json <<EOF
{
  "gitlab_cloud_token": "${GITLAB_CLOUD_TOKEN}",
  "mirror_group_id": ${MIRROR_GROUP_ID},
  "pi_gitlab_url": "http://localhost",
  "pi_gitlab_token": "${GITLAB_RUNNER_TOKEN}",
  "domain": "${DOMAIN}",
  "hostname": "${HOSTNAME}"
}
EOF

# Create mirror script
echo "[i] Creating mirror script..."
cat > /srv/gitlab-mirror/mirror-repos.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/srv/gitlab-mirror/config.json"
LOG_FILE="/srv/gitlab-mirror/mirror.log"

# Load configuration
GITLAB_CLOUD_TOKEN=$(jq -r '.gitlab_cloud_token' "$CONFIG_FILE")
MIRROR_GROUP_ID=$(jq -r '.mirror_group_id' "$CONFIG_FILE")
PI_GITLAB_URL=$(jq -r '.pi_gitlab_url' "$CONFIG_FILE")
PI_GITLAB_TOKEN=$(jq -r '.pi_gitlab_token' "$CONFIG_FILE")

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get all projects from Pi GitLab
get_pi_projects() {
  curl -s --header "PRIVATE-TOKEN: ${PI_GITLAB_TOKEN}" \
    "${PI_GITLAB_URL}/api/v4/projects?per_page=100" | \
    jq -r '.[] | select(.archived == false) | "\(.id)|\(.name)|\(.path_with_namespace)"'
}

# Check if project exists on GitLab Cloud
project_exists_on_cloud() {
  local project_path="$1"
  curl -s --header "PRIVATE-TOKEN: ${GITLAB_CLOUD_TOKEN}" \
    "https://gitlab.com/api/v4/projects/${project_path//\//%2F}" >/dev/null 2>&1
}

# Create project on GitLab Cloud
create_cloud_project() {
  local project_name="$1"
  local project_path="$2"
  local description="$3"

  curl -s --header "PRIVATE-TOKEN: ${GITLAB_CLOUD_TOKEN}" \
    --header "Content-Type: application/json" \
    --request POST \
    "https://gitlab.com/api/v4/projects" \
    --data "{
      \"name\": \"${project_name}\",
      \"path\": \"${project_name}\",
      \"namespace_id\": ${MIRROR_GROUP_ID},
      \"description\": \"${description}\",
      \"visibility\": \"private\",
      \"mirror\": true
    }" >/dev/null
}

# Mirror repository
mirror_repository() {
  local pi_project_id="$1"
  local project_name="$2"
  local project_path="$3"

  log "Mirroring project: $project_path"

  # Get project details from Pi
  local project_info=$(curl -s --header "PRIVATE-TOKEN: ${PI_GITLAB_TOKEN}" \
    "${PI_GITLAB_URL}/api/v4/projects/${pi_project_id}")

  local description=$(echo "$project_info" | jq -r '.description // "Mirrored from Pi GitLab"')

  # Create project on GitLab Cloud if it doesn't exist
  if ! project_exists_on_cloud "${MIRROR_GROUP_ID}/${project_name}"; then
    log "Creating project on GitLab Cloud: $project_name"
    create_cloud_project "$project_name" "${MIRROR_GROUP_ID}/${project_name}" "$description"
  fi

  # Set up mirroring from Pi to Cloud
  curl -s --header "PRIVATE-TOKEN: ${GITLAB_CLOUD_TOKEN}" \
    --header "Content-Type: application/json" \
    --request POST \
    "https://gitlab.com/api/v4/projects/${MIRROR_GROUP_ID}%2F${project_name}/remote_mirrors" \
    --data "{
      \"url\": \"${PI_GITLAB_URL}/${project_path}.git\",
      \"enabled\": true,
      \"keep_divergent_refs\": false
    }" >/dev/null

  log "Mirroring configured for: $project_path"
}

# Main mirroring process
main() {
  log "Starting repository mirroring process"

  local projects
  projects=$(get_pi_projects)

  if [[ -z "$projects" ]]; then
    log "No projects found on Pi GitLab"
    return 0
  fi

  echo "$projects" | while IFS='|' read -r project_id project_name project_path; do
    mirror_repository "$project_id" "$project_name" "$project_path"
  done

  log "Repository mirroring process completed"
}

main "$@"
EOF

chmod +x /srv/gitlab-mirror/mirror-repos.sh

# Create webhook handler for automatic mirroring
echo "[i] Creating webhook handler..."
cat > /srv/gitlab-mirror/webhook-handler.py <<'EOF'
#!/usr/bin/env python3
import json
import subprocess
import sys
from datetime import datetime

def log(message):
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] {message}")

def handle_webhook(payload):
    try:
        data = json.loads(payload)
        event_type = data.get('object_kind')

        if event_type in ['push', 'merge_request', 'project_create']:
            log(f"Triggering mirror for event: {event_type}")
            result = subprocess.run(
                ['/srv/gitlab-mirror/mirror-repos.sh'],
                capture_output=True,
                text=True
            )

            if result.returncode == 0:
                log("Mirroring completed successfully")
            else:
                log(f"Mirroring failed: {result.stderr}")
        else:
            log(f"Ignoring event type: {event_type}")

    except Exception as e:
        log(f"Error handling webhook: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        handle_webhook(sys.argv[1])
    else:
        # Read from stdin
        payload = sys.stdin.read()
        handle_webhook(payload)
EOF

chmod +x /srv/gitlab-mirror/webhook-handler.py

# Create systemd service for webhook handler
echo "[i] Creating webhook service..."
sudo tee /etc/systemd/system/gitlab-mirror-webhook.service >/dev/null <<EOF
[Unit]
Description=GitLab Mirror Webhook Handler
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/srv/gitlab-mirror
ExecStart=/usr/bin/python3 /srv/gitlab-mirror/webhook-handler.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create cron job for periodic mirroring
echo "[i] Setting up periodic mirroring..."
(crontab -l 2>/dev/null | grep -v gitlab-mirror; echo "0 */6 * * * /srv/gitlab-mirror/mirror-repos.sh >> /srv/gitlab-mirror/mirror.log 2>&1") | crontab -

# Run initial mirroring
echo "[i] Running initial repository mirroring..."
/srv/gitlab-mirror/mirror-repos.sh

# Start webhook service
echo "[i] Starting webhook service..."
sudo systemctl enable gitlab-mirror-webhook
sudo systemctl start gitlab-mirror-webhook

echo ""
echo "GitLab Cloud mirroring setup complete!"
echo ""
echo "Configuration:"
echo "  Mirror group: https://gitlab.com/groups/${HOSTNAME}-mirror"
echo "  Config file: /srv/gitlab-mirror/config.json"
echo "  Log file: /srv/gitlab-mirror/mirror.log"
echo ""
echo "Manual mirroring: /srv/gitlab-mirror/mirror-repos.sh"
echo "Webhook service: sudo systemctl status gitlab-mirror-webhook"
echo ""
echo "Add webhook to your Pi GitLab:"
echo "  URL: http://$(hostname -I | awk '{print $1}'):8080/webhook"
echo "  Events: Push events, Merge request events, Project events"
