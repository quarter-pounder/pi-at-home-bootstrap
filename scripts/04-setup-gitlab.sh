#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

echo "[i] Creating GitLab directories..."
sudo mkdir -p /srv/gitlab/{data,logs,config}
sudo mkdir -p /srv/gitlab-runner/config
sudo mkdir -p /srv/registry
sudo chown -R "${USERNAME}:${USERNAME}" /srv/gitlab*
sudo chown -R "${USERNAME}:${USERNAME}" /srv/registry

echo "[i] Generating GitLab configuration..."
# Ensure all required variables are set
export DOMAIN="${DOMAIN:-REDACTED.run}"
export GITLAB_DOMAIN="${GITLAB_DOMAIN:-gitlab.${DOMAIN}}"
export GITLAB_EXTERNAL_URL="${GITLAB_EXTERNAL_URL:-https://gitlab.${DOMAIN}}"
export TIMEZONE="${TIMEZONE:-UTC}"
export GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD:-REDACTED}"
export GITLAB_IMAGE="${GITLAB_IMAGE:-gitlab/gitlab-ce:latest}"

# Generate configuration with proper variable substitution
envsubst < config/gitlab.rb.template > compose/gitlab.rb

# Verify no grafana references
if grep -i grafana compose/gitlab.rb; then
  echo "[!] WARNING: Grafana references found in generated config!"
  exit 1
fi

echo "[i] GitLab configuration generated successfully"

echo "[i] Generating compose file with variables..."
envsubst < compose/gitlab.yml > compose/gitlab-resolved.yml

echo "[i] Starting GitLab services..."
cd compose
docker compose -f compose/gitlab-resolved.yml up -d

echo "[i] Waiting for GitLab to become healthy (this may take 5-10 minutes)..."
for i in {1..60}; do
  if docker exec gitlab gitlab-rake gitlab:check SANITIZE=true >/dev/null 2>&1; then
    echo "[i] GitLab is healthy!"
    break
  fi
  echo "[i] Still waiting... ($i/60)"
  sleep 10
done

echo "[i] GitLab root password: ${GITLAB_ROOT_PASSWORD}"
echo "[i] Please log in to GitLab and create a runner registration token."
echo "[i] Then add it to .env as GITLAB_RUNNER_TOKEN and run: scripts/05-register-runner.sh"
echo "[i] GitLab is accessible at: ${GITLAB_EXTERNAL_URL}"

