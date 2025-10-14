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
docker exec -it gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "http://gitlab" \
  --token "${GITLAB_RUNNER_TOKEN}" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --description "gitlab-pi-runner" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-network-mode "gitlab-network"

echo "[i] Runner registered successfully!"
docker exec gitlab-runner gitlab-runner verify

