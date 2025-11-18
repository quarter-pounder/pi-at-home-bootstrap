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
CADVISOR_URL="${CADVISOR_URL:-http://127.0.0.1:8080}"

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
api_endpoint="${CADVISOR_URL}/api/v1.3/docker/${short_id}"
api_payload=$(curl -sf "${api_endpoint}" || true)

if [[ -z "${api_payload}" ]]; then
  echo "Failed to query cadvisor API at ${CADVISOR_URL}" >&2
  exit 1
fi

# Debug: check if stats array exists and has elements
stats_count=$(echo "${api_payload}" | jq '.stats | length // 0')
if [[ "${stats_count}" -eq 0 ]]; then
  echo "Warning: stats array is empty or missing" >&2
  echo "API response structure:" >&2
  echo "${api_payload}" | jq 'keys' >&2
fi

api_usage=$(echo "${api_payload}" | jq '.stats[-1].memory.usage // empty')
api_working_set=$(echo "${api_payload}" | jq '.stats[-1].memory.working_set // empty')

printf 'Container: %s (%s)\n' "${CONTAINER_NAME}" "${short_id}"
printf 'cgroup memory.current: %s bytes\n' "${cgroup_bytes}"

if [[ -n "${api_usage}" ]] && [[ "${api_usage}" != "null" ]] && [[ "${api_usage}" != "empty" ]]; then
  printf 'cadvisor memory.usage: %s bytes\n' "${api_usage}"
else
  echo 'cadvisor memory.usage: (absent)'
  # Debug: show what we got
  echo "  Debug: jq returned: '${api_usage}'" >&2
  echo "  Debug: last stats element keys:" >&2
  echo "${api_payload}" | jq '.stats[-1] | keys' >&2 || true
fi

if [[ -n "${api_working_set}" ]] && [[ "${api_working_set}" != "null" ]] && [[ "${api_working_set}" != "empty" ]]; then
  printf 'cadvisor memory.working_set: %s bytes\n' "${api_working_set}"
else
  echo 'cadvisor memory.working_set: (absent)'
  # Debug: show what we got
  echo "  Debug: jq returned: '${api_working_set}'" >&2
fi

