```
pi-forge/
├── bootstrap/                      # Tier 0 — minimal setup, pure bash
│   ├── install.sh
│   ├── 00-preflight.sh
│   ├── 01-install-core.sh
│   ├── 02-install-docker.sh
│   ├── 03-verify.sh
│   └── utils.sh
│
├── config-registry/                # Centralized configuration (source of truth)
│   ├── env/                        # Declarative inputs (human-maintained)
│   │   ├── base.env               # Universal settings
│   │   ├── secrets.env.vault      # Encrypted secrets
│   │   ├── domains.yml            # Active domains + dependencies (declarative needs)
│   │   ├── ports.yml              # Port assignments (assigned bindings)
│   │   └── overrides/             # Environment-specific overrides
│   │       ├── dev.env
│   │       ├── staging.env
│   │       └── prod.env
│   ├── schema/                     # Validation and defaults (machine rules)
│   │   ├── env.schema.yml         # Required fields, defaults, types
│   │   ├── domains.schema.yml
│   │   └── ports.schema.yml       # Enforces naming: {domain: {port_name: number}}
│   ├── templates/                  # Global templates (pure render outputs)
│   │   ├── compose.yml.tmpl
│   │   ├── network.yml.tmpl
│   │   ├── terraform.tfvars.tmpl
│   │   ├── ansible-vars.yml.tmpl
│   │   └── cloud-init.tmpl
│   └── generate-metadata.sh        # Generates domains/*/metadata.yml
│
├── domains/                        # Tier 2 — composable service domains
│   ├── gitlab/
│   │   ├── metadata.yml           # Generated (from domains.yml + ports.yml)
│   │   ├── templates/              # Static (uses $PORT_* vars)
│   │   │   ├── compose.yml.tmpl
│   │   │   ├── gitlab.rb.tmpl
│   │   │   └── runner-config.toml.tmpl
│   │   ├── scripts/                # Lifecycle operations
│   │   │   ├── setup.sh
│   │   │   ├── register-runner.sh
│   │   │   ├── backup.sh
│   │   │   └── restore.sh
│   │   └── README.md
│   │
│   ├── monitoring/
│   │   ├── metadata.yml           # Generated
│   │   ├── templates/              # Static (uses $PORT_* vars)
│   │   │   ├── compose.yml.tmpl
│   │   │   ├── prometheus.yml.tmpl
│   │   │   ├── prometheus-alerts.yml.tmpl
│   │   │   ├── alertmanager.yml.tmpl
│   │   │   ├── loki.yml.tmpl
│   │   │   ├── alloy.river.tmpl
│   │   │   ├── grafana-datasource.yml.tmpl
│   │   │   └── dashboards/
│   │   ├── scripts/setup.sh
│   │   └── README.md
│   │
│   ├── adblocker/
│   │   ├── metadata.yml           # Generated
│   │   ├── templates/              # Static
│   │   │   ├── compose.yml.tmpl
│   │   │   └── unbound.conf.tmpl
│   │   └── README.md
│   │
│   └── tunnel/
│       ├── metadata.yml           # Generated
│       ├── templates/              # Static
│       │   ├── compose.yml.tmpl
│       │   └── config.yml.tmpl
│       └── README.md
│
├── infra/                          # Tier 1 — infrastructure & IaC
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars.example
│   │   └── modules/
│   │       ├── aws/
│   │       │   ├── main.tf
│   │       │   ├── outputs.tf
│   │       │   └── variables.tf
│   │       ├── gcp/
│   │       │   ├── main.tf
│   │       │   ├── outputs.tf
│   │       │   └── variables.tf
│   │       └── cloudflare/
│   │           ├── main.tf
│   │           ├── outputs.tf
│   │           └── variables.tf
│   └── ansible/
│       ├── playbooks/
│       ├── roles/
│       └── group_vars/
│
├── common/                         # Shared utilities
│   ├── Makefile
│   ├── utils.sh
│   ├── validate.sh                # Reconciles domains vs ports vs metadata
│   ├── render-config.sh           # Injects $PORT_* vars into templates
│   ├── link-domain.sh
│   └── generate-manifest.sh
│
├── backup/                         # Cross-domain backup logic
│   ├── policy.yml
│   └── scripts/
│       ├── backup.sh
│       ├── restore.sh
│       └── verify.sh
│
├── generated/                      # Generated files (git-ignored)
│   └── <domain>/
│       ├── compose.yml            # Rendered from templates
│       ├── network.yml
│       └── ...
│
├── examples/
│   ├── gitlab-ci-docker.yml
│   ├── gitlab-ci-nodejs.yml
│   ├── gitlab-ci-python.yml
│   └── README.md
│
└── MANIFEST.md
```
---

## Key Design Principles

### 1. Configuration Hierarchy (Source of Truth)

**Declarative Flow:**
```
config-registry/env/domains.yml  ← declarative needs
config-registry/env/ports.yml    ← assigned bindings
          │
          ▼
generate-metadata.sh            → outputs domains/*/metadata.yml (generated)
          │
          ▼
validate.sh                     → reconciles domains vs ports vs metadata
          │
          ▼
render-config.sh                → injects $PORT_* vars into templates
domains/*/templates/*.tmpl      → → generated/*/*.yml
```

**Environment Loading:**
```
base.env → overrides/<env>.env → decrypted secrets.env
          ↓
      (validate against schema/)
          ↓
      Available as $VAR_NAME in templates
```

**Workflow Examples:**
- **Add new domain**: Declare in `domains.yml` → Assign ports in `ports.yml` → Run `generate-metadata.sh` → Done
- **Change a port**: Update `ports.yml` → Run `generate-metadata.sh` → Downstream render reflects change

### 2. Immutable vs Mutable
- **Immutable** (version controlled): configs, IaC, Dockerfile, compose templates
- **Mutable** (runtime data): `/srv/<domain>/data/`, database files, TSDB, backups
- Store mutable in `/srv/<domain>/`; version everything else in git

### 3. Local vs Cloud Separation
- **Local (Pi)**: Docker Compose, application configs, backup scripts
- **Cloud (Terraform)**: DNS records, storage buckets, tunnel configs
- **Hybrid**: DR mirroring (runs on both)
- Keep separation clear: terraform/ handles cloud only, domains/ handles local only

### 4. Configuration Flow
```bash
# Initial setup or after changing domains.yml/ports.yml
make generate-metadata    # Generate metadata.yml files
make validate            # Validate configuration
make render DOMAIN=gitlab ENV=prod
make deploy DOMAIN=gitlab

# Or for multiple domains
make generate-metadata
make validate
make render DOMAIN=gitlab ENV=prod
make render DOMAIN=monitoring ENV=prod
make deploy DOMAIN=gitlab
make deploy DOMAIN=monitoring
```

### 5. Loose Coupling via metadata.yml
- **metadata.yml is generated** from `domains.yml` + `ports.yml`
- Provides machine-readable summary per domain (for validation and introspection)
- Each domain declares its own dependencies in `domains.yml`
- Optional vs required dependencies clearly marked
- Port conflict detection via `validate.sh` (reconciles metadata vs registry)
- Services work standalone or together (e.g., Prometheus without Grafana)

### 6. Version Locking & Drift Detection
- Lock Docker image tags in compose.yml
- Pin Terraform provider versions
- Auto-generate MANIFEST.md: image digests, config hashes, git commit IDs
- Validate configs before deploy to detect drift

### 7. Secrets Management
- Ansible-vault
- Consider Hashicorp Vault for multi-host future (Would I need that other than testing the waters?)
- Decrypt **only** during render phase

### 8. Backup & Recovery Isolation
- Cross-domain backup logic in backup/scripts/
- Domain-specific backup/restore in domains/<domain>/scripts/
- Recovery procedures independent of domain setup

### 9. Network Strategy
- Domains can use shared or isolated Docker networks (defined in metadata.yml? to be decided)
- Cloudflare Tunnel runs in its own domain (tunnel/)
- Internal networks for true isolation; external networks for service discovery

### 10. Dependency Resolution
```yaml
# domains/grafana/metadata.yml
dependencies:
  - prometheus  # Hard requirement
  - loki        # Optional, graceful degradation
optional_dependencies:
  - postgres    # For remote storage
```
Makefile's `link` target validates and wires dependencies
Note: remember to check port conflicts

---

## Reference Implementations

### common/Makefile
```makefile
.PHONY: env generate-metadata render deploy destroy validate validate-schema manifest

ENV ?= dev
DOMAIN ?= gitlab

env:
	@echo "[Env] Loading environment $(ENV)"
	@set -a; source config-registry/env/base.env; set +a

generate-metadata:
	@echo "[Generate] Creating metadata.yml files"
	@bash config-registry/generate-metadata.sh

validate: generate-metadata
	@echo "[Validate] Runtime validation (fast, minimal)"
	@bash common/validate.sh

validate-schema:
	@echo "[Validate] Schema validation (CI enforcement)"
	@yq -o=json config-registry/env/domains.yml | ajv validate \
	  -s config-registry/schema/domains.schema.yml
	@yq -o=json config-registry/env/ports.yml | ajv validate \
	  -s config-registry/schema/ports.schema.yml

render: validate
	@echo "[Render] $(DOMAIN) for $(ENV)"
	@bash common/render-config.sh $(DOMAIN) $(ENV)

deploy: render
	@echo "[Deploy] $(DOMAIN)"
	@docker compose -f generated/$(DOMAIN)/compose.yml up -d

destroy:
	@docker compose -f generated/$(DOMAIN)/compose.yml down -v

manifest:
	@bash common/generate-manifest.sh
```

### config-registry/generate-metadata.sh
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[Generate] Creating metadata.yml files from domains.yml + ports.yml"

# Read domains.yml and ports.yml
# Merge port assignments into domain definitions
# Output per-domain metadata.yml files to domains/<name>/metadata.yml

for domain in $(yq '.domains[].name' config-registry/env/domains.yml); do
  tmp=$(mktemp)

  # Generate metadata.yml by combining domain definition + port assignments
  # Write to temp file
  # ... (generate logic here) ... > "$tmp"

  # Only update if content changed (preserves file mtime if unchanged)
  if ! cmp -s "$tmp" "domains/$domain/metadata.yml" 2>/dev/null; then
    mv "$tmp" "domains/$domain/metadata.yml"
    echo "  Updated domains/$domain/metadata.yml"
  else
    rm "$tmp"
    echo "  No changes to domains/$domain/metadata.yml"
  fi
done

echo "[Generate] Metadata files generated"
```

### common/render-config.sh
```bash
#!/usr/bin/env bash
set -euo pipefail

DOMAIN="$1"
ENVIRONMENT="${2:-dev}"

echo "[Render] $DOMAIN for environment $ENVIRONMENT"

SRC="domains/${DOMAIN}/templates"
DST="generated/${DOMAIN}"
mkdir -p "$DST"

# Load environment (layered: base → override → secrets)
set -a
source config-registry/env/base.env
[ -f "config-registry/env/overrides/${ENVIRONMENT}.env" ] && source "config-registry/env/overrides/${ENVIRONMENT}.env"
# Decrypt and source secrets
if [ -f config-registry/env/secrets.env.vault ]; then
  ansible-vault decrypt --vault-password-file .vault_pass config-registry/env/secrets.env.vault --output /tmp/secrets.env
  source /tmp/secrets.env
  rm /tmp/secrets.env
fi
# Load ports.yml as PORT_* variables
# ports.yml structure: {domain: {port_name: number}}
# Converts to: PORT_{DOMAIN}_{PORT_NAME} (uppercase)
# Example: gitlab.http: 8080 → PORT_GITLAB_HTTP=8080
eval $(yq -o=shell config-registry/env/ports.yml | \
  awk -F'=' '{
    gsub(/^ports_/, "", $1);
    gsub(/_/, "_", $1);
    print "PORT_" toupper($1) "=" $2
  }')
set +a

# Render templates (templates use $PORT_* vars)
for f in "$SRC"/*.tmpl; do
  out="$DST/$(basename "${f%.tmpl}")"
  envsubst < "$f" > "$out"
  echo "rendered $out"
done

echo "[Render] Complete"
```

### common/validate.sh (Runtime - Fast, Minimal)
```bash
#!/usr/bin/env bash
set -e

echo "[Validate] Runtime validation (fast, minimal)..."

# Fast YAML syntax checks (no external dependencies)
yq eval '.domains | keys' config-registry/env/domains.yml >/dev/null || {
  echo "Error: Invalid YAML syntax in domains.yml"
  exit 1
}

yq eval 'keys' config-registry/env/ports.yml >/dev/null || {
  echo "Error: Invalid YAML syntax in ports.yml"
  exit 1
}

# Check port conflicts (duplicate port numbers)
used_ports=$(yq '.[] | .[]' config-registry/env/ports.yml | sort | uniq -d)
if [ -n "$used_ports" ]; then
  echo "Error: Port conflicts detected: $used_ports"
  exit 1
fi

# Quick validation: Every domain in domains.yml has ports in ports.yml
# ... (basic structural checks)

echo "[Validate] Runtime checks passed"
```

### CI Schema Validation (Makefile target)
```bash
# validate-schema: Full JSON Schema validation with ajv (CI enforcement)
# Requires Node.js/ajv in CI environment
yq -o=json config-registry/env/domains.yml | ajv validate \
  -s config-registry/schema/domains.schema.yml
yq -o=json config-registry/env/ports.yml | ajv validate \
  -s config-registry/schema/ports.schema.yml
```

### common/link-domain.sh
```bash
#!/usr/bin/env bash
set -e

DOMAIN=$1
DEPENDENCY=$2

echo "[Link] Wiring $DOMAIN to $DEPENDENCY"
docker network connect ${DEPENDENCY}-net ${DOMAIN} || true
```

### common/generate-manifest.sh
```bash
#!/usr/bin/env bash
set -e

echo "Generating manifest..."
{
  echo "# Manifest generated $(date)"
  echo ""
  echo "## Git State"
  git rev-parse HEAD
  git status --short
  echo ""
  echo "## Docker Images"
  docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | sort
  echo ""
  echo "## Config Checksums"
  find generated -type f | xargs sha256sum
} > MANIFEST.md

echo "Manifest generated: MANIFEST.md"
```

### domains/gitlab/metadata.yml (GENERATED)
```yaml
# This file is auto-generated by generate-metadata.sh
# Do not edit manually - edit config-registry/env/domains.yml and ports.yml instead
# Port references use PORT_{DOMAIN}_{PORT_NAME} format from ports.yml

domain: gitlab
description: GitLab CE and Runner for self-hosted CI/CD
version: latest

depends_on: []

exports:
  ports:
    http: ${PORT_GITLAB_HTTP}      # From ports.yml: gitlab.http
    https: ${PORT_GITLAB_HTTPS}    # From ports.yml: gitlab.https
    ssh: ${PORT_GITLAB_SSH}        # From ports.yml: gitlab.ssh
    metrics: ${PORT_GITLAB_METRICS} # From ports.yml: gitlab.metrics

  endpoints:
    web: https://gitlab.${DOMAIN}
    metrics: http://gitlab:${PORT_GITLAB_METRICS}/metrics

networks:
  - gitlab-net

volumes:
  - /srv/gitlab/config
  - /srv/gitlab/data
  - /srv/gitlab/logs
```

### bootstrap/install.sh
```bash
#!/usr/bin/env bash
set -e

echo "[Bootstrap] Starting minimal setup..."

bash bootstrap/00-preflight.sh
bash bootstrap/01-install-core.sh
bash bootstrap/02-install-docker.sh
bash bootstrap/03-verify.sh

echo "[Bootstrap] Complete. Docker ready."
```
