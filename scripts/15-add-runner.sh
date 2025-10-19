#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

echo "Add Additional GitLab Runner"
echo "============================"
echo ""

if [[ -z "${GITLAB_RUNNER_TOKEN:-}" ]]; then
  echo "GITLAB_RUNNER_TOKEN not set in .env"
  echo "Get token from: GitLab → Admin → CI/CD → Runners"
  exit 1
fi

read -p "Runner name [gitlab-pi-runner-2]: " RUNNER_NAME
RUNNER_NAME=${RUNNER_NAME:-gitlab-pi-runner-2}

read -p "Runner executor (docker/shell) [docker]: " EXECUTOR
EXECUTOR=${EXECUTOR:-docker}

read -p "Concurrent jobs for this runner [2]: " CONCURRENT
CONCURRENT=${CONCURRENT:-2}

echo ""
echo "${YELLOW}Registering new runner: ${RUNNER_NAME}${RESET}"

if [[ "$EXECUTOR" == "docker" ]]; then
  docker exec -it gitlab-runner gitlab-runner register \
    --non-interactive \
    --url "http://gitlab" \
    --token "${GITLAB_RUNNER_TOKEN}" \
    --executor "docker" \
    --docker-image "alpine:latest" \
    --description "${RUNNER_NAME}" \
    --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
    --docker-network-mode "gitlab-network" \
    --docker-pull-policy "if-not-present"
else
  docker exec -it gitlab-runner gitlab-runner register \
    --non-interactive \
    --url "http://gitlab" \
    --token "${GITLAB_RUNNER_TOKEN}" \
    --executor "shell" \
    --description "${RUNNER_NAME}"
fi

echo ""
echo "${YELLOW}Updating runner concurrency...${RESET}"
docker exec gitlab-runner sed -i "s/concurrent = .*/concurrent = $CONCURRENT/" /etc/gitlab-runner/config.toml

echo ""
echo "${YELLOW}Restarting runner...${RESET}"
docker restart gitlab-runner

echo ""
echo "${GREEN}Runner added successfully!${RESET}"
echo ""
echo "Verify in GitLab: Admin → CI/CD → Runners"
echo ""
docker exec gitlab-runner gitlab-runner verify

