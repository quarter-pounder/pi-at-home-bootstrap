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
│   ├── env/                        # Human-authored, declarative inputs
│   │   ├── base.env               # Universal settings
│   │   ├── secrets.env.vault      # Encrypted secrets
│   │   ├── domains.yml            # Active domains + placement/relationships
│   │   ├── ports.yml              # Port assignments (assigned bindings)
│   │   └── overrides/             # Environment-specific overrides
│   │       ├── dev.env
│   │       ├── staging.env
│   │       └── prod.env
│   ├── schema/                     # Validation rules (machine rules)
│   │   ├── domains.schema.yml
│   │   └── ports.schema.yml
│   ├── templates/                  # Machine templates (pure render outputs)
│   │   ├── compose.yml.tmpl
│   │   ├── network.yml.tmpl
│   │   ├── terraform.tfvars.tmpl
│   │   ├── ansible-vars.yml.tmpl
│   │   └── cloud-init.tmpl
│   ├── state/                      # Ephemeral, auto-generated (git-ignored)
│   │   ├── metadata-cache/        # Intermediate (pre-commit) generation output
│   │   │   ├── forgejo.yml
│   │   │   ├── postgres.yml
│   │   │   ├── woodpecker.yml
│   │   │   ├── woodpecker-runner.yml
│   │   │   └── ...
│   │   └── env-resolved/          # Cached merged env (for debugging/performance)
│   │       ├── dev.env
│   │       ├── staging.env
│   │       └── prod.env
│
├── domains/                        # Tier 2 — composable service domains
│   ├── forgejo/
│   │   ├── metadata.yml           # Final reconciled, version-controlled output
│   │   ├── templates/              # Static (compose/app.ini)
│   │   │   ├── compose.yml.tmpl
│   │   │   └── app.ini.tmpl
│   │   └── README.md
│   │
│   ├── postgres/
│   │   ├── metadata.yml
│   │   ├── templates/
│   │   │   ├── compose.yml.tmpl
│   │   │   └── init.sql.tmpl
│   │   └── README.md
│   │
│   ├── woodpecker/
│   │   ├── metadata.yml
│   │   ├── templates/
│   │   │   └── compose.yml.tmpl
│   │   └── README.md
│   │
│   ├── woodpecker-runner/
│   │   ├── metadata.yml
│   │   ├── templates/
│   │   │   └── compose.yml.tmpl
│   │   └── README.md
│   │
│   ├── monitoring/
│   │   ├── metadata.yml           # Final reconciled, version-controlled output
│   │   ├── templates/              # Static (uses Jinja2 + env context)
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
│   │   ├── metadata.yml           # Final reconciled, version-controlled output
│   │   ├── templates/              # Static
│   │   │   ├── compose.yml.tmpl
│   │   │   └── unbound.conf.tmpl
│   │   └── README.md
│   │
│   └── tunnel/
│       ├── metadata.yml           # Final reconciled, version-controlled output
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
│   ├── validate.sh                # Runtime validation (wraps Python helpers)
│   ├── render_config.py           # Jinja2 renderer for domain templates
│   ├── metadata.py                # Metadata generate/diff/commit/check
│   ├── lib/
│   │   ├── check_ports.py
│   │   ├── check_images.py
│   │   ├── check_terraform.py
│   │   └── env.sh
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
├── examples/                       # Legacy GitLab CI pipeline examples (reference only)
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
Declarative (human intent)
  config-registry/env/domains.yml  ← declarative needs (placement/relationships)
  config-registry/env/ports.yml    ← assigned bindings
          │
          ▼
Machine generation (cached)
  metadata.py generate            → outputs config-registry/state/metadata-cache/*.yml
          │
          ▼
Validated truth (versioned metadata)
  diff state/metadata-cache/ vs domains/*/metadata.yml
  cp state/metadata-cache/*.yml → domains/*/metadata.yml (commit)
          │
          ▼
Rendered runtime (ephemeral)
  validate.py / validate.sh        → reconciles domains vs ports vs metadata (Python helpers)
  render_config.py                → renders Jinja2 templates into generated/
  domains/*/templates/*.tmpl      → → generated/*/*.yml
```

**State Directory:**
- `config-registry/state/` = transient machine output (git-ignored)
  - For diagnostics, caching, CI diffing
- `domains/<name>/metadata.yml` = canonical generated artifact (version-controlled)
  - Treated as versioned truth for each domain

**Environment Loading:**
```
base.env → overrides/<env>.env → decrypted secrets.env
          ↓
      (validate against schema/)
          ↓
      Available as $VAR_NAME in templates
```

**Workflow Examples:**
- **Add new domain**:
  1. Declare in `domains.yml` → Assign ports in `ports.yml`
  2. Run `make generate-metadata` → Creates `state/metadata-cache/<domain>.yml`
  3. Review diff: `diff -u state/metadata-cache/<domain>.yml domains/<domain>/metadata.yml`
  4. Commit: `cp state/metadata-cache/<domain>.yml domains/<domain>/metadata.yml`
- **Change a port**:
  1. Update `ports.yml`
  2. Run `make generate-metadata` → Updates `state/metadata-cache/*.yml`
  3. Review and commit changes to `domains/*/metadata.yml`
  4. Downstream render reflects change

_Reminder: capturing `requires`, `exposes_to`, and `consumes` may feel like extra modelling today, but it preserves the memory of which stacks (monitoring, tunnel, registry, etc.) rely on each domain so future-you doesn’t have to reverse engineer dependencies._

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
make render DOMAIN=forgejo ENV=prod
make deploy DOMAIN=forgejo

# Or for multiple domains
make generate-metadata
make validate
make render DOMAIN=forgejo ENV=prod
make render DOMAIN=monitoring ENV=prod
make render DOMAIN=woodpecker ENV=prod
make deploy DOMAIN=forgejo
make deploy DOMAIN=monitoring
make deploy DOMAIN=woodpecker
```

### 5. Loose Coupling via metadata.yml
**metadata.yml generation flow:**
  1. `metadata.py generate` creates `config-registry/state/metadata-cache/*.yml` (ephemeral)
  2. Review diff: `diff -u state/metadata-cache/<domain>.yml domains/<domain>/metadata.yml`
  3. Commit canonical version: `cp state/metadata-cache/<domain>.yml domains/<domain>/metadata.yml`
- Provides machine-readable summary per domain (placement, requires, exposures) for validation and introspection
- Each domain declares its runtime prerequisites via `requires` and its consumers via `exposes_to`
- Optional vs required relationships clearly marked
- Metadata includes `_meta.source_hash` to track source file changes

### Forgejo Domain Strategy
- Treat Forgejo + PostgreSQL as the core code-hosting pair; inputs are rendered `app.ini` and database DSNs, outputs are HTTP/SSH endpoints plus `/metrics`.
- Runtime state lives under `/srv/forgejo/{config,data,log}` with relational data in the shared PostgreSQL domain. Manage lifecycle via compose and database dumps—no interactive mutations.
- Regenerate config through Jinja templates (`domains/forgejo/templates/app.ini.tmpl`, `compose.yml.tmpl`) and redeploy; rotate secrets via the vault.
- Container registry support is externalized: the standalone `registry` domain reuses Forgejo’s token service; Woodpecker CI integrates through OAuth + shared agent secrets.

### 6. Version Locking & Drift Detection
- Legacy reference material remains in `/legacy` until v2 stabilises; plan to archive or relocate once new domains are fully operational.

- Lock Docker image tags in compose.yml
- Pin Terraform provider versions
- Auto-generate MANIFEST.md: image digests, config hashes, git commit IDs
- Validate configs before deploy to detect drift
- Metadata drift detection: `make diff-metadata` compares `state/metadata-cache/` vs `domains/*/metadata.yml`
- Optional watchdog daemon monitors `config-registry/state/metadata-cache/*.yml` and surfaces drift events (see docs/tools/metadata-watchdog.md).
- `metadata.py generate` and the watchdog use a lightweight flock-based lock (`config-registry/state/.lock`) to avoid concurrent runs.
- Metadata `_meta` includes `generated_at`, `git_commit`, and `source_hash` (templates + metadata) for traceability.
- Watchdog can run under systemd (see docs/tools/metadata-watchdog.md for unit example).

- Metadata includes `_meta.source_hash` to track source file changes

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

### 10. Relationship Modelling
```yaml
# domains/grafana/metadata.yml
requires:
  - prometheus        # Hard requirement
consumes:
  - loki              # Optional, graceful degradation
exposes_to:
  - tunnel            # Dashboards surfaced via tunnel
```
Makefile targets can inspect `requires`/`consumes` to build dependency graphs.
Note: remember to check port conflicts

---

## Reference Implementations

### common/Makefile
```makefile
.PHONY: env generate-metadata commit-metadata diff-metadata render deploy destroy validate validate-schema manifest

ENV ?= dev
DOMAIN ?= forgejo

env:
	@echo "[Env] Loading environment $(ENV)"
	@set -a; source config-registry/env/base.env; set +a

generate-metadata:
	@echo "[Generate] Creating metadata cache files"
	@cd $(ROOT_DIR) && python3 common/metadata.py generate

commit-metadata: generate-metadata
	@echo "[Commit] Reviewing metadata diffs..."
	@cd $(ROOT_DIR) && python3 common/metadata.py commit

diff-metadata: generate-metadata
	@echo "[Diff] Checking metadata drift..."
	@cd $(ROOT_DIR) && python3 common/metadata.py diff

validate: generate-metadata
	@echo "[Validate] Runtime validation (fast, minimal)"
	@cd $(ROOT_DIR) && bash common/validate.sh

validate-schema:
	@echo "[Validate] Schema validation (CI enforcement)"
	@yq -o=json config-registry/env/domains.yml | ajv validate \
	  -s config-registry/schema/domains.schema.yml
	@yq -o=json config-registry/env/ports.yml | ajv validate \
	  -s config-registry/schema/ports.schema.yml

render: generate-metadata
	@echo "[Render] $(DOMAIN) for $(ENV)"
	@cd $(ROOT_DIR) && python3 common/render_config.py --domain $(DOMAIN) --env $(ENV)

deploy: render
	@echo "[Deploy] $(DOMAIN)"
	@docker compose -f generated/$(DOMAIN)/compose.yml up -d

destroy:
	@docker compose -f generated/$(DOMAIN)/compose.yml down -v

manifest:
	@bash common/generate-manifest.sh
```

### common/metadata.py
```bash
# Generate cache files for all domains
python3 common/metadata.py generate

# Compare cache vs canonical (ignoring _meta.generated_at)
python3 common/metadata.py diff

# Copy cache into domains/<name>/metadata.yml
python3 common/metadata.py commit

# Convenience wrapper: generate + diff (exit 1 on drift)
python3 common/metadata.py check
```

### common/render_config.py
```python
import argparse

def render(domain, env):
    # Load environment variables
    # This part would typically involve loading base.env, overrides/<env>.env, and secrets.env.vault
    # For simplicity, we'll just simulate loading a dummy env file
    print(f"Rendering for {domain} in {env} environment...")
    print("Loading dummy environment variables...")
    # In a real scenario, you'd load:
    # import os
    # os.environ.update(load_env_file("config-registry/env/base.env"))
    # os.environ.update(load_override_env(env))
    # os.environ.update(load_secrets_env())

    # Load ports and domain metadata
    # This would involve reading config-registry/env/ports.yml and domains/<domain>/metadata.yml
    # For simplicity, we'll just simulate loading a dummy ports file and metadata
    print("Loading dummy ports and metadata...")
    # In a real scenario, you'd load:
    # ports_data = load_ports_file("config-registry/env/ports.yml")
    # domain_metadata = load_domain_metadata(domain)

    # Render templates
    # This would involve Jinja2 rendering of domains/<domain>/templates/*.tmpl
    # For simplicity, we'll just print a placeholder
    print("Rendering templates...")
    # In a real scenario, you'd use:
    # from jinja2 import Environment, FileSystemLoader
    # env = Environment(loader=FileSystemLoader("domains/"))
    # rendered_compose = env.get_template("compose.yml.tmpl").render(domain_metadata)
    # rendered_network = env.get_template("network.yml.tmpl").render(domain_metadata)
    # rendered_terraform = env.get_template("terraform.tfvars.tmpl").render(domain_metadata)
    # rendered_ansible = env.get_template("ansible-vars.yml.tmpl").render(domain_metadata)
    # rendered_cloud_init = env.get_template("cloud-init.tmpl").render(domain_metadata)

    # Save rendered files
    # For simplicity, we'll just print the paths
    print(f"Generated files for {domain}:")
    print("  - generated/$(domain)/compose.yml")
    print("  - generated/$(domain)/network.yml")
    print("  - generated/$(domain)/terraform.tfvars")
    print("  - generated/$(domain)/ansible-vars.yml")
    print("  - generated/$(domain)/cloud-init.tmpl")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Render domain templates")
    parser.add_argument("--domain", required=True)
    parser.add_argument("--env", default="dev")
    parser.add_argument("--dry-run", action="store_true", help="Print available context keys and exit")
    args = parser.parse_args()

    try:
        render(args.domain, args.env, dry_run=args.dry_run)
    except FileNotFoundError as exc:
        log_warn(str(exc))
```
- `DRY_RUN=1 make render DOMAIN=monitoring` will invoke the renderer with `--dry-run` and list all context keys without writing files.

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

### Example: domains/forgejo/metadata.yml
```yaml
_meta:
  generated_at: "2024-01-15T10:30:00Z"
  source_hash: "abc123def456..."
  domain: forgejo

name: forgejo
ports:
  http: 3001
  ssh: 2222
networks:
  - forgejo-network
dependencies:
  - postgres
# ... (domain-specific metadata) ...
```

**Note:** The `_meta` field is generated automatically and used for drift detection. It should not be manually edited.

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
  docker compose -f generated/${DOMAIN}/compose.yml config | yq '.services[].image' | xargs -n1 docker inspect --format '{{.RepoDigests}}'
  echo ""
  echo "## Config Checksums"
  find generated -type f | xargs sha256sum
  echo "## Domain Checksums"
  find domains -name metadata.yml | xargs sha256sum
} > MANIFEST.md

echo "Manifest generated: MANIFEST.md"
```

### domains/forgejo/metadata.yml (GENERATED)
```yaml
# This file is auto-generated by metadata.py generate
# Do not edit manually - edit config-registry/env/domains.yml and ports.yml instead
# Port references use PORT_{DOMAIN}_{PORT_NAME} format from ports.yml

domain: forgejo
description: Forgejo code hosting service
version: latest

depends_on: []

exports:
  ports:
    http: ${PORT_FORGEJO_HTTP}     # From ports.yml: forgejo.http
    ssh: ${PORT_FORGEJO_SSH}       # From ports.yml: forgejo.ssh

  endpoints:
    web: https://forgejo.${DOMAIN}
    metrics: http://forgejo:${PORT_FORGEJO_HTTP}/metrics

networks:
  - forgejo-network

volumes:
  - /srv/forgejo/config
  - /srv/forgejo/data
  - /srv/forgejo/log
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
