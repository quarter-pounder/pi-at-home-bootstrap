#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions Runner Management Script
# Handles adding, removing, and managing multiple runner instances

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNNERS_DIR="${ROOT_DIR}/config-registry/env/runners"
ACTION="${1:-}"
RUNNER_NAME="${2:-}"

usage() {
  cat <<EOF
Usage: $0 <action> <name> [options]

Actions:
  add <name>           - Add a new runner instance
  down <name>          - Bring down a runner instance
  destroy <name>       - Destroy a runner instance (removes data)
  list                 - List all runner instances
  render <name>        - Render compose file for a runner
  deploy <name>        - Deploy a runner instance

Options for 'add':
  --repo-url <url>     - Repository URL (e.g., https://github.com/owner/repo)
  --token <token>      - Registration token from GitHub
  --labels <labels>    - Comma-separated labels (default: self-hosted,Linux,ARM64)
  --docker-enabled     - Enable Docker support (default: true)

Examples:
  $0 add pi-runner --repo-url https://github.com/user/repo --token <token>
  $0 down pi-runner
  $0 destroy pi-runner
  $0 list
EOF
  exit 1
}

ensure_runners_dir() {
  mkdir -p "${RUNNERS_DIR}"
}

get_runner_env_file() {
  echo "${RUNNERS_DIR}/github-actions-runner-${RUNNER_NAME}.env"
}

get_runner_data_dir() {
  echo "/srv/github-actions-runner-${RUNNER_NAME}"
}

get_runner_compose_file() {
  echo "${ROOT_DIR}/generated/github-actions-runner-${RUNNER_NAME}/compose.yml"
}

add_runner() {
  if [[ -z "${RUNNER_NAME}" ]]; then
    echo "Error: Runner name required" >&2
    usage
  fi

  local env_file
  env_file=$(get_runner_env_file)

  if [[ -f "${env_file}" ]]; then
    echo "Error: Runner '${RUNNER_NAME}' already exists" >&2
    exit 1
  fi

  # Parse arguments
  local repo_url=""
  local token=""
  local labels="self-hosted,Linux,ARM64"
  local docker_enabled="true"

  shift 2
  while [[ $# -gt 0 ]]; do
    case $1 in
      --repo-url)
        repo_url="$2"
        shift 2
        ;;
      --token)
        token="$2"
        shift 2
        ;;
      --labels)
        labels="$2"
        shift 2
        ;;
      --docker-enabled)
        docker_enabled="${2:-true}"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        ;;
    esac
  done

  if [[ -z "${token}" ]]; then
    echo "Error: --token is required" >&2
    exit 1
  fi

  ensure_runners_dir

  # Create env file
  cat > "${env_file}" <<EOF
# GitHub Actions Runner: ${RUNNER_NAME}
GITHUB_ACTIONS_RUNNER_NAME=${RUNNER_NAME}
GITHUB_ACTIONS_RUNNER_REPO_URL=${repo_url}
GITHUB_ACTIONS_RUNNER_TOKEN=${token}
GITHUB_ACTIONS_RUNNER_LABELS=${labels}
GITHUB_ACTIONS_RUNNER_DOCKER_ENABLED=${docker_enabled}
EOF

  echo "Created runner configuration: ${env_file}"
  echo ""
  echo "Next steps:"
  echo "  1. Review and edit ${env_file} if needed"
  echo "  2. Run: make render-github-runner NAME=${RUNNER_NAME}"
  echo "  3. Run: make deploy-github-runner NAME=${RUNNER_NAME}"
}

list_runners() {
  ensure_runners_dir

  local runners
  runners=$(find "${RUNNERS_DIR}" -name "github-actions-runner-*.env" -type f 2>/dev/null | sort || true)

  if [[ -z "${runners}" ]]; then
    echo "No runners configured"
    return 0
  fi

  echo "Configured runners:"
  for env_file in ${runners}; do
    local name
    name=$(basename "${env_file}" .env | sed 's/github-actions-runner-//')
    local repo_url
    repo_url=$(grep "^GITHUB_ACTIONS_RUNNER_REPO_URL=" "${env_file}" 2>/dev/null | cut -d'=' -f2- || echo "not set")
    local status
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^github-actions-runner-${name}$"; then
      status="running"
    else
      status="stopped"
    fi
    printf "  %-20s %-10s %s\n" "${name}" "${status}" "${repo_url}"
  done
}

down_runner() {
  if [[ -z "${RUNNER_NAME}" ]]; then
    echo "Error: Runner name required" >&2
    usage
  fi

  local compose_file
  compose_file=$(get_runner_compose_file)

  if [[ ! -f "${compose_file}" ]]; then
    echo "Error: Runner '${RUNNER_NAME}' not deployed (compose file not found)" >&2
    exit 1
  fi

  echo "Bringing down runner: ${RUNNER_NAME}"
  cd "${ROOT_DIR}" && docker compose -f "${compose_file}" down

  # Create alert suppression marker
  if [[ -d "/srv/monitoring/alert-suppression" ]]; then
    touch "/srv/monitoring/alert-suppression/github-actions-runner-${RUNNER_NAME}.down"
    echo "Alert suppression enabled for github-actions-runner-${RUNNER_NAME}"
  fi
}

destroy_runner() {
  if [[ -z "${RUNNER_NAME}" ]]; then
    echo "Error: Runner name required" >&2
    usage
  fi

  local compose_file
  compose_file=$(get_runner_compose_file)
  local data_dir
  data_dir=$(get_runner_data_dir)
  local env_file
  env_file=$(get_runner_env_file)

  # Bring down container and remove volumes
  if [[ -f "${compose_file}" ]]; then
    echo "Stopping and removing container..."
    cd "${ROOT_DIR}" && docker compose -f "${compose_file}" down -v || true
  fi

  # Remove data directory
  if [[ -d "${data_dir}" ]]; then
    echo "Removing data directory: ${data_dir}"
    read -p "This will delete all runner data. Continue? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rm -rf "${data_dir}"
    else
      echo "Skipped data directory removal"
    fi
  fi

  # Remove env file
  if [[ -f "${env_file}" ]]; then
    echo "Removing configuration: ${env_file}"
    rm -f "${env_file}"
  fi

  # Remove generated files
  local generated_dir
  generated_dir="${ROOT_DIR}/generated/github-actions-runner-${RUNNER_NAME}"
  if [[ -d "${generated_dir}" ]]; then
    echo "Removing generated files: ${generated_dir}"
    rm -rf "${generated_dir}"
  fi

  # Remove alert suppression marker
  if [[ -f "/srv/monitoring/alert-suppression/github-actions-runner-${RUNNER_NAME}.down" ]]; then
    rm -f "/srv/monitoring/alert-suppression/github-actions-runner-${RUNNER_NAME}.down"
  fi

  echo "Runner '${RUNNER_NAME}' destroyed"
}

render_runner() {
  if [[ -z "${RUNNER_NAME}" ]]; then
    echo "Error: Runner name required" >&2
    usage
  fi

  local env_file
  env_file=$(get_runner_env_file)

  if [[ ! -f "${env_file}" ]]; then
    echo "Error: Runner '${RUNNER_NAME}' not found. Run 'add' first." >&2
    exit 1
  fi

  # Source base env and runner-specific env
  cd "${ROOT_DIR}"
  set -a
  source config-registry/env/base.env
  source .env 2>/dev/null || true
  source "${env_file}"
  set +a

  # Create generated directory
  local generated_dir
  generated_dir="generated/github-actions-runner-${RUNNER_NAME}"
  mkdir -p "${generated_dir}"

  # Render compose file
  python3 common/render_config.py \
    --domain github-actions-runner \
    --env dev \
    --extra-env "${env_file}"

  # Move generated files to runner-specific directory
  if [[ -d "generated/github-actions-runner" ]]; then
    mkdir -p "${generated_dir}"
    mv generated/github-actions-runner/* "${generated_dir}/" 2>/dev/null || true
    rmdir generated/github-actions-runner 2>/dev/null || true
  fi

  echo "Rendered compose file: ${generated_dir}/compose.yml"
}

deploy_runner() {
  if [[ -z "${RUNNER_NAME}" ]]; then
    echo "Error: Runner name required" >&2
    usage
  fi

  local compose_file
  compose_file=$(get_runner_compose_file)

  if [[ ! -f "${compose_file}" ]]; then
    echo "Compose file not found. Rendering first..."
    render_runner "${RUNNER_NAME}"
  fi

  echo "Deploying runner: ${RUNNER_NAME}"
  cd "${ROOT_DIR}" && docker compose -f "${compose_file}" up -d --pull always

  # Remove alert suppression marker if it exists
  if [[ -f "/srv/monitoring/alert-suppression/github-actions-runner-${RUNNER_NAME}.down" ]]; then
    rm -f "/srv/monitoring/alert-suppression/github-actions-runner-${RUNNER_NAME}.down"
    echo "Alert suppression removed for github-actions-runner-${RUNNER_NAME}"
  fi
}

case "${ACTION}" in
  add)
    add_runner "$@"
    ;;
  list)
    list_runners
    ;;
  down)
    down_runner
    ;;
  destroy)
    destroy_runner
    ;;
  render)
    render_runner
    ;;
  deploy)
    deploy_runner
    ;;
  *)
    usage
    ;;
esac

