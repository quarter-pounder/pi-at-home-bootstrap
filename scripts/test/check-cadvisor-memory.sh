#!/usr/bin/env bash
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not available" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl command not available" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq command not available" >&2
  exit 1
fi

CONTAINER_NAME="${1:-forgejo}"
CADVISOR_URL="${CADVISOR_URL:-http://localhost:8080}"

container_id=$(docker inspect --format '{{.Id}}' "${CONTAINER_NAME}" 2>/dev/null || true)
if [[ -z "${container_id}" ]]; then
  echo "Container \"${CONTAINER_NAME}\" not found" >&2
  exit 1
fi

short_id=${container_id:0:12}

cgroup_path="/sys/fs/cgroup/system.slice/docker-${container_id}.scope/memory.current"
if [[ ! -f "${cgroup_path}" ]]; then
  echo "cgroup memory file not found at ${cgroup_path}" >&2
  exit 1
fi

cgroup_bytes=$(cat "${cgroup_path}")
api_payload=$(curl -sf "${CADVISOR_URL}/api/v1.3/containers/docker/${short_id}" || true)

if [[ -z "${api_payload}" ]]; then
  echo "Failed to query cadvisor API at ${CADVISOR_URL}" >&2
  exit 1
fi

api_usage=$(echo "${api_payload}" | jq '.[-1].memory.usage // empty')
api_working_set=$(echo "${api_payload}" | jq '.[-1].memory.working_set // empty')

printf 'Container: %s (%s)\n' "${CONTAINER_NAME}" "${short_id}"
printf 'cgroup memory.current: %s bytes\n' "${cgroup_bytes}"

if [[ -n "${api_usage}" ]]; then
  printf 'cadvisor memory.usage: %s bytes\n' "${api_usage}"
else
  echo 'cadvisor memory.usage: (absent)'
fi

if [[ -n "${api_working_set}" ]]; then
  printf 'cadvisor memory.working_set: %s bytes\n' "${api_working_set}"
else
  echo 'cadvisor memory.working_set: (absent)'
fi

