#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

source "$PROJECT_ROOT/common/utils.sh"

log_info "Runtime validation (fast, minimal)..."

# Ensure required files exist
for f in config-registry/env/base.env config-registry/env/domains.yml config-registry/env/ports.yml; do
  if [[ ! -f "$f" ]]; then
    log_error "Missing required file: $f"
    exit 1
  fi
done

# Fast YAML syntax checks
yq eval '.domains | keys' config-registry/env/domains.yml >/dev/null || {
  log_error "Invalid YAML syntax in domains.yml"
  exit 1
}

yq eval 'keys' config-registry/env/ports.yml >/dev/null || {
  log_error "Invalid YAML syntax in ports.yml"
  exit 1
}

# Check port conflicts (flatten numeric leaves)
used_ports=$(yq '.. | select(tag == "!!int")' config-registry/env/ports.yml | sort | uniq -d)
if [[ -n "$used_ports" ]]; then
  log_error "Port conflicts detected: $used_ports"
  exit 1
fi

# Ensure every domain has ports defined
DOMAINS=$(yq '.domains[].name' config-registry/env/domains.yml)
for domain in $DOMAINS; do
  if ! yq -e ".$domain" config-registry/env/ports.yml >/dev/null 2>&1; then
    log_warn "Domain '$domain' has no ports defined in ports.yml"
  fi
done

# Ensure every ports entry corresponds to a domain
PORT_DOMAINS=$(yq 'keys' config-registry/env/ports.yml | yq '.[]')
for port_domain in $PORT_DOMAINS; do
  if ! yq -e ".domains[] | select(.name == \"$port_domain\")" config-registry/env/domains.yml >/dev/null 2>&1; then
    log_warn "Port domain '$port_domain' not found in domains.yml"
  fi
done

log_success "Runtime checks passed"
