#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

if [[ -z "${GITLAB_RUNNER_TOKEN:-}" ]]; then
  echo "[!] GITLAB_RUNNER_TOKEN not set in .env"
  echo "[i] Get token from GitLab: Admin Area > CI/CD > Runners > New instance runner"
  exit 1
fi

echo "[i] Registering GitLab Runner..."
# Create a custom config file to skip TLS verification
docker exec gitlab-runner sh -c 'cat > /etc/gitlab-runner/config.toml << EOF
concurrent = 1
check_interval = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "gitlab-pi-runner"
  url = "${GITLAB_EXTERNAL_URL}"
  token = "'${GITLAB_RUNNER_TOKEN}'"
  executor = "docker"
  tls_skip_verify = true
  [runners.custom_build_dir]
  [runners.cache]
  [runners.docker]
    tls_verify = false
    image = "alpine:latest"
    privileged = false
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = ["/var/run/docker.sock:/var/run/docker.sock"]
    network_mode = "gitlab-network"
EOF'

echo "[i] Runner registered successfully!"
echo "[i] Skipping verification due to TLS certificate issues..."
echo "[i] Runner should be available in GitLab UI"

