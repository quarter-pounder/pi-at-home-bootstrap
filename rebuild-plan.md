pi-at-home/
├── bootstrap/                      # Tier 0 — minimal setup, pure bash
│   ├── install.sh
│   ├── 00-preflight.sh
│   ├── 01-install-core.sh
│   ├── 02-install-docker.sh
│   ├── 03-verify.sh
│   └── utils.sh
│
├── config-registry/                # Centralized configuration (source of truth)
│   ├── env/
│   │   ├── base.env
│   │   ├── secrets.env.vault
│   │   ├── ports.yml
│   │   └── domains.yml
│   ├── templates/
│   │   ├── compose.yml.tmpl
│   │   ├── network.yml.tmpl
│   │   └── terraform.tfvars.tmpl
│   └── render-config.sh
│
├── domains/                        # Tier 2 — composable service domains
│   ├── gitlab/
│   │   ├── metadata.yml
│   │   ├── templates/
│   │   │   ├── compose.yml.tmpl
│   │   │   ├── gitlab.rb.tmpl
│   │   │   └── runner-config.toml.tmpl
│   │   ├── scripts/
│   │   │   ├── setup.sh
│   │   │   ├── register-runner.sh
│   │   │   ├── backup.sh
│   │   │   └── restore.sh
│   │   └── README.md
│   │
│   ├── monitoring/
│   │   ├── metadata.yml
│   │   ├── templates/
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
│   │   ├── metadata.yml
│   │   ├── templates/
│   │   │   ├── compose.yml.tmpl
│   │   │   └── unbound.conf.tmpl
│   │   └── README.md
│   │
│   └── tunnel/
│       ├── metadata.yml
│       ├── templates/
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
│   ├── validate.sh
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
├── generated/                      # Rendered configs (git-ignored, not versioned)
│   ├── gitlab/
│   ├── monitoring/
│   └── tunnel/
│
├── examples/
│   ├── gitlab-ci-docker.yml
│   ├── gitlab-ci-nodejs.yml
│   ├── gitlab-ci-python.yml
│   └── README.md
│
├── docs/
│   ├── README.md
│   ├── ARCHITECTURE.md
│   ├── SETUP.md
│   └── OPERATIONS.md
│
└── MANIFEST.md                     # Generated: image digests, config hashes, git state

---

## Key Design Principles

### 1. Configuration Hierarchy (Source of Truth)
```
.env (base + secrets)
  → metadata.yml (domain definitions)
    → render-config.sh (derives everything)
      → compose.yml, terraform vars, ansible vars
        → Runtime
```

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
make load-env ENV=prod
make setup DOMAIN=gitlab
make setup DOMAIN=monitoring
make link DOMAIN=grafana DEPENDS_ON=prometheus
make validate
make manifest
```

### 5. Loose Coupling via metadata.yml
- Each domain declares its own dependencies
- Optional vs required dependencies clearly marked
- Port conflict detection via validate.sh
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
.PHONY: env render deploy destroy validate manifest

ENV ?= dev
DOMAIN ?= gitlab

env:
	@echo "[Env] Loading environment $(ENV)"
	@set -a; source config-registry/env/base.env; set +a

render: env
	@echo "[Render] $(DOMAIN) for $(ENV)"
	@bash config-registry/render-config.sh $(DOMAIN) $(ENV)

deploy: render validate
	@echo "[Deploy] $(DOMAIN)"
	@docker compose -f generated/$(DOMAIN)/compose.yml up -d

destroy:
	@docker compose -f generated/$(DOMAIN)/compose.yml down -v

validate:
	@bash common/validate.sh

manifest:
	@bash common/generate-manifest.sh
```

### config-registry/render-config.sh
```bash
#!/usr/bin/env bash
set -euo pipefail

DOMAIN="$1"
ENVIRONMENT="${2:-dev}"

echo "[Render] $DOMAIN for environment $ENVIRONMENT"

SRC="domains/${DOMAIN}/templates"
DST="generated/${DOMAIN}"
mkdir -p "$DST"

# Load environment
set -a
source config-registry/env/base.env
[ -f "config-registry/env/${ENVIRONMENT}.env" ] && source "config-registry/env/${ENVIRONMENT}.env"
set +a

# Render templates
for f in "$SRC"/*.tmpl; do
  out="$DST/$(basename "${f%.tmpl}")"
  envsubst < "$f" > "$out"
  echo "rendered $out"
done

echo "[Render] Complete"
```

### common/validate.sh
```bash
#!/usr/bin/env bash
set -e

echo "[Validate] Checking port conflicts..."

# Extract ports from metadata files
used_ports=$(find domains -name metadata.yml -exec yq '.exports.ports | keys | .[]' {} \; | sort | uniq)
duplicates=$(echo "$used_ports" | sort | uniq -d)

if [ -n "$duplicates" ]; then
  echo "Port conflicts detected: $duplicates"
  exit 1
fi

echo "No port conflicts"
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

### domains/gitlab/metadata.yml
```yaml
domain: gitlab
description: GitLab CE and Runner for self-hosted CI/CD
version: latest

depends_on: []

exports:
  ports:
    http: 8080      # Internal Puma port
    https: 443      # Published HTTPS
    ssh: 2222       # Published SSH
    metrics: 9152   # Workhorse Prometheus metrics (internal)

  endpoints:
    web: https://gitlab.{DOMAIN}
    metrics: http://gitlab:9152/metrics

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
