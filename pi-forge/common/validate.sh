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

# Check port conflicts with domain context
if [[ -s config-registry/env/ports.yml ]]; then
port_conflicts=$(yq -o=json config-registry/env/ports.yml | python3 - <<'PY'
import json, sys

data = json.load(sys.stdin)
conflicts = []
by_port = {}

if isinstance(data, dict):
    for domain, ports in data.items():
        if not isinstance(ports, dict):
            continue
        for name, value in ports.items():
            if isinstance(value, int):
                by_port.setdefault(value, []).append(f"{domain}.{name}")

for port, mappings in by_port.items():
    if len(mappings) > 1:
        conflicts.append(f"Port {port} used by {', '.join(mappings)}")

if conflicts:
    print("\n".join(conflicts))
PY
)
fi

if [[ -n "$port_conflicts" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && log_error "$line"
  done <<< "$port_conflicts"
  exit 1
fi

# Ensure Docker images have explicit, pinned tags
image_report=$(python3 - <<'PY'
from pathlib import Path
import re

bad = []
paths = [p for p in Path('domains').rglob('*')
         if p.is_file() and any(p.name.endswith(ext) for ext in ('.yml', '.yaml', '.tmpl'))]
for path in paths:
    try:
        text = path.read_text()
    except Exception:
        continue
    for lineno, line in enumerate(text.splitlines(), 1):
        if not re.match(r'^\s*image:\s+', line):
            continue
        value = line.split('image:', 1)[1]
        value = value.split('#', 1)[0].strip().strip('\"\'')
        if not value or '$' in value or '{{' in value:
            continue
        if '@sha256:' in value:
            continue
        if ':' not in value:
            bad.append(f"{path}:{lineno} image tag missing (expected <repo>:<tag>)")
        else:
            tag = value.rsplit(':', 1)[1]
            if tag == '' or tag.lower() == 'latest':
                bad.append(f"{path}:{lineno} image tag must be pinned (found '{value}')")

if bad:
    print("\n".join(bad))
PY
)

if [[ -n "$image_report" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && log_error "$line"
  done <<< "$image_report"
  exit 1
fi

# Ensure Terraform providers are pinned
if [[ -d infra/terraform ]]; then
  tf_report=$(python3 - <<'PY'
from pathlib import Path
import re

tf_dir = Path('infra/terraform')
if not tf_dir.exists():
    raise SystemExit

bad = []
for path in tf_dir.rglob('*.tf'):
    try:
        text = path.read_text()
    except Exception:
        continue
    for block in re.finditer(r'required_providers\s*{([^}]*)}', text, re.DOTALL):
        body = block.group(1)
        for match in re.finditer(r'(\w+)\s*=\s*{([^}]*)}', body, re.DOTALL):
            provider, conf = match.groups()
            if 'version' not in conf:
                bad.append(f"{path}:{provider}")

if bad:
    print("\n".join(bad))
PY
  )

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

# Ensure canonical metadata contains traceability fields
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

log_success "[Validate] Runtime checks passed in ${SECONDS}s"
