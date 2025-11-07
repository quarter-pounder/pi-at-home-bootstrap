#!/usr/bin/env bash
set -euo pipefail
SECONDS=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

source "$PROJECT_ROOT/common/utils.sh"

log_info "Runtime validation (fast, minimal)..."

for cmd in yq python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Missing required command: $cmd"
    exit 1
  fi
done

if ! compgen -G "domains/*/metadata.yml" >/dev/null; then
  log_error "No metadata.yml files found under domains/"
  exit 1
fi

for f in \
  config-registry/env/base.env \
  config-registry/env/domains.yml \
  config-registry/env/ports.yml; do
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

if [[ -s config-registry/env/ports.yml ]]; then
  port_conflicts=$(python3 common/lib/check_ports.py)
else
  port_conflicts=""
fi

if [[ -n "$port_conflicts" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && log_error "$line"
  done <<< "$port_conflicts"
  exit 1
fi

image_report=$(python3 common/lib/check_images.py)

if [[ -n "$image_report" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && log_error "$line"
  done <<< "$image_report"
  exit 1
fi

if [[ -d infra/terraform ]]; then
  tf_report=$(python3 common/lib/check_terraform.py)

  if [[ -n "$tf_report" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && log_error "Terraform provider missing version pin: $line"
    done <<< "$tf_report"
    exit 1
  fi

  if [[ ! -f infra/terraform/.terraform.lock.hcl ]]; then
    log_warn "infra/terraform/.terraform.lock.hcl not found (run terraform init to generate lockfile)"
  fi
fi

missing_meta=0
for file in domains/*/metadata.yml; do
  [[ -f "$file" ]] || continue
  if ! yq -e '._meta.git_commit' "$file" >/dev/null 2>&1; then
    log_error "Metadata missing _meta.git_commit: $file"
    missing_meta=1
  fi
  if ! yq -e '._meta.source_hash' "$file" >/dev/null 2>&1; then
    log_error "Metadata missing _meta.source_hash: $file"
    missing_meta=1
  fi
done

if (( missing_meta )); then
  log_error "One or more metadata.yml files are missing traceability fields (_meta.git_commit / _meta.source_hash)"
  exit 1
fi

for file in domains/*/metadata.yml; do
  domain=$(basename "$(dirname "$file")")
  if ! yq -e ".domains[] | select(.name == \"$domain\")" config-registry/env/domains.yml >/dev/null 2>&1; then
    log_warn "Metadata file '$file' has no corresponding domain entry in domains.yml"
  fi
done

DOMAINS=$(yq '.domains[].name' config-registry/env/domains.yml)
for domain in $DOMAINS; do
  if ! yq -e ".$domain" config-registry/env/ports.yml >/dev/null 2>&1; then
    if [[ "$domain" != "tunnel" ]]; then
      log_warn "Domain '$domain' has no ports defined in ports.yml"
    fi
  fi
done

PORT_DOMAINS=$(yq 'keys' config-registry/env/ports.yml | yq '.[]')
for port_domain in $PORT_DOMAINS; do
  if ! yq -e ".domains[] | select(.name == \"$port_domain\")" config-registry/env/domains.yml >/dev/null 2>&1; then
    log_warn "Port domain '$port_domain' not found in domains.yml"
  fi
done

log_success "[Validate] Runtime checks passed in ${SECONDS}s"
