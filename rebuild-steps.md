# Rebuild Steps

Roadmap for reconstructing the repo into the new domain-driven structure.
Each phase builds safely on the previous one; all steps are idempotent and reversible.
Each should be self-contained.

---

## Phase 0 – Preparation

- [x] Create a backup branch:
  ```bash
  git checkout -b legacy-snapshot
  git tag v1.0.0-legacy
  ```
- [x] Move existing structure to `pi-forge/legacy/`:
  ```bash
  mkdir -p legacy
  mv compose/ config/ scripts/ terraform/ backup/ examples/ pi-forge/legacy/
  mv *.md *.sh *.txt *.yml pi-forge/legacy/ 2>/dev/null || true
  ```
- [x] Initialize new folder structure:
  ```bash
  mkdir -p pi-forge/{bootstrap,config-registry,domains,infra,common,backup,generated,examples,docs}
  ```
- [x] Backup existing data:
  ```bash
  sudo tar -czf /tmp/srv-backup-$(date +%Y%m%d).tar.gz /srv/
  ```
- [x] Document Cloudflare Tunnel dashboard settings in `pi-forge/legacy/CF_TUNNEL_SETTINGS.md`
- [x] Confirm minimal host dependencies:
  `bash`, `docker`, `docker compose`, `jq`, `yq`, `envsubst`, `ansible-vault`.

---

## Phase 1 – Bootstrap (Tier 0)

**Goal:** Minimal host setup with Docker ready and optimized for Pi.

- [x] Move install scripts into `bootstrap/`:
  - [x] `install.sh`
  - [x] `00-migrate-to-nvme.sh` (optional, for SD to NVMe migration)
  - [x] `01-preflight.sh`
  - [x] `02-install-core.sh`
  - [x] `03-install-docker.sh`
  - [x] `04-optimize-docker.sh`
  - [x] `05-verify.sh`
- [x] Strip GitLab-specific logic; only system + Docker setup.
- [x] Create `04-optimize-docker.sh`:
  - [x] Configure Docker daemon with Pi-optimized settings
  - [x] Set overlay2 storage driver
  - [x] Configure log rotation and IP pools
  - [x] Enable live-restore and disable userland-proxy
  - [x] Set appropriate ulimits
  - [x] Restart Docker daemon to apply changes
- [x] Enhance `05-verify.sh` with Pi-specific checks:
  - [x] Verify `/srv` mount point and NVMe device detection
  - [x] Check Docker daemon status via systemctl
  - [x] Validate memory and swap availability
  - [x] Check disk space on `/srv` partition
  - [x] Verify Docker storage driver (overlay2)
  - [x] Validate network interfaces
  - [x] Optional disk throughput test (skip with `SKIP_THROUGHPUT_TEST=1`)
- [x] Test standalone:
  ```bash
  # Optional: Migrate to NVMe first (if needed)
  # sudo bash bootstrap/00-migrate-to-nvme.sh

  sudo bash bootstrap/01-preflight.sh
  sudo bash bootstrap/02-install-core.sh
  sudo bash bootstrap/03-install-docker.sh
  sudo bash bootstrap/04-optimize-docker.sh
  bash bootstrap/05-verify.sh
  ```
- [x] Confirm Docker works and `/srv` is mounted on NVMe.

---

## Phase 2 – Configuration Registry

**Goal:** Establish single source of truth with encrypted secrets, metadata generation, and validation.

### 2.1 – Directory Structure

- [x] Create `config-registry/` directory structure:
  ```bash
  mkdir -p config-registry/{env/overrides,schema,templates,state/{metadata-cache,env-resolved}}
  ```

### 2.2 – Environment Configuration

- [x] Create `config-registry/env/base.env` (from legacy `.env`):
  - Universal settings (DOMAIN, TIMEZONE, etc.)
  - Non-sensitive configuration
- [ ] Create `config-registry/env/secrets.env.vault` with ansible-vault:
  ```bash
  ansible-vault create config-registry/env/secrets.env.vault
  # Add: GITLAB_ROOT_PASSWORD, GRAFANA_ADMIN_PASSWORD, SMTP_PASSWORD, etc.
  ```
- [ ] Create `config-registry/env/overrides/` directory:
  - [ ] `dev.env` - Development environment overrides
  - [ ] `staging.env` - Staging environment overrides
  - [ ] `prod.env` - Production environment overrides

### 2.3 – Declarative Configuration

- [ ] Create `config-registry/env/ports.yml` with port assignments:
  ```yaml
  gitlab:
    http: 8080
    https: 443
    ssh: 2222
  monitoring:
    prometheus: 9090
    grafana: 3000
    loki: 3100
  # ... (all domains)
  ```
  **Note:** Naming convention: `{domain: {port_name: number}}` → `PORT_{DOMAIN}_{PORT_NAME}`

- [ ] Create `config-registry/env/domains.yml`:
  ```yaml
  domains:
    - name: gitlab
      placement: tunnel
      standalone: false
      requires: []
      exposes_to: [tunnel, monitoring]
      consumes: []
    - name: monitoring
      placement: local
      standalone: true
      requires: []
      exposes_to: []
      consumes: [gitlab]
  ```

### 2.4 – Schema Validation

- [ ] Create `config-registry/schema/env.schema.yml`:
  - Required fields, defaults, types
  - Validation rules for environment variables
- [ ] Create `config-registry/schema/domains.schema.yml`:
  - Domain structure validation
  - Placement / requires / exposes validation
- [ ] Create `config-registry/schema/ports.schema.yml`:
  - Enforces naming convention: `{domain: {port_name: number}}`
  - Port conflict detection rules

### 2.5 – Metadata Generation

- [ ] Implement `config-registry/generate-metadata.sh`:
  - Reads `domains.yml` and `ports.yml`
  - Merges port assignments into domain definitions
  - Generates `_meta` field with `generated_at`, `source_hash`, `domain`
  - Outputs to `config-registry/state/metadata-cache/*.yml`
  - Uses atomic file writes (temp file + cmp + mv)

### 2.6 – Validation Scripts

- [ ] Implement `common/validate.sh` (runtime - fast, minimal):
  - Fast YAML syntax checks with `yq`
  - Port conflict detection
  - Basic structural validation
  - No external dependencies (bash/yq only)

- [ ] Add `validate-schema` target to `common/Makefile`:
  - Full JSON Schema validation with `ajv` (CI enforcement)
  - Validates `domains.yml` and `ports.yml` against schemas
  - Requires Node.js/ajv (CI environment)

### 2.7 – Makefile Targets

- [ ] Create `common/Makefile` with targets:
  - `make generate-metadata` - Creates `state/metadata-cache/*.yml`
  - `make diff-metadata` - Checks for drift (exits 1 if drift found)
  - `make commit-metadata` - Reviews diffs and copies to `domains/*/metadata.yml`
  - `make validate` - Runtime validation (fast, minimal)
  - `make validate-schema` - Schema validation (CI enforcement)
  - `make render DOMAIN=<name> ENV=<env>` - Renders templates
  - `make deploy DOMAIN=<name>` - Deploys domain
  - `make env ENV=<env>` - Loads environment variables

### 2.8 – Configuration Rendering

- [ ] Implement Python-based renderer (`common/render_config.py` + thin `render-config.sh` wrapper):
  - Layered environment loading: `base.env` → `overrides/<env>.env` → `secrets.env`
  - Decrypts `secrets.env.vault` only during render (temporary in-memory view via `ansible-vault view`)
  - Loads `ports.yml` as both structured data and `PORT_*` env-style variables
  - Renders Jinja2 templates from `domains/<domain>/templates/` to `generated/<domain>/`
  - Declare dependencies in `requirements/render.txt` (install via `pip install -r requirements/render.txt` or apt packages `python3-jinja2`, `python3-yaml`)

### 2.9 – Git Configuration

- [ ] Update `.gitignore`:
  - `pi-forge/generated/`
  - `pi-forge/config-registry/state/`
  - `pi-forge/.vault_pass`
  - `pi-forge/config-registry/env/secrets.env` (decrypted)

### 2.10 – Testing & Verification

- [ ] Test metadata generation:
  ```bash
  make generate-metadata
  ls config-registry/state/metadata-cache/
  ```

- [ ] Test drift detection:
  ```bash
  make diff-metadata
  # Should show no drift initially
  ```

- [ ] Test metadata commit workflow:
  ```bash
  make commit-metadata
  # Review diffs, then commit domains/*/metadata.yml
  ```

- [ ] Test validation:
  ```bash
  make validate
  make validate-schema  # Requires Node.js/ajv
  ```

- [ ] Smoke-test render (after Phase 3 domain templates exist):
  ```bash
  make render DOMAIN=gitlab ENV=dev
  ls generated/gitlab/
  ```

### 2.11 – Documentation

- [ ] Document workflow in `rebuild-plan.md`:
  - Declarative flow: `domains.yml` + `ports.yml` → `generate-metadata.sh` → `metadata.yml`
  - State directory purpose (ephemeral vs versioned)
  - Port naming convention and conversion
  - Two-tier validation approach

### 2.12 – Makefile & Validation Hardening

- [ ] Move Makefile inline shell into `common/lib/*.sh` helpers
  - [ ] Implement `metadata_diff`, `metadata_commit`, `load_env` helpers
  - [ ] Source helpers in Make targets
- [ ] Introduce composite target `metadata-check` (`make generate-metadata && make diff-metadata`)
- [ ] Extend `common/validate.sh`
  - [ ] Fail if Docker images use `:latest` or omit tags in templates/metadata
  - [ ] Fail if Terraform providers lack explicit version pins / lockfile
  - [ ] Ensure metadata `_meta` includes `git_commit` / `source_hash`

### 2.13 – Metadata Watchdog

- [ ] Create `tools/metadata_watchdog.py` (Python) to monitor `config-registry/state/metadata-cache/`
  - [ ] Watch for file changes (watchdog/inotify), debounce events
  - [ ] Compare cache vs `domains/<name>/metadata.yml`
  - [ ] Log warning (and optional diff) when drift detected
  - [ ] Support `--auto-diff` to run `make diff-metadata`
- [ ] Add requirements entry (e.g., `requirements/watchdog.txt`)
- [ ] Document usage in `docs/tools/metadata-watchdog.md`
  - [ ] Describe systemd unit example
  - [ ] Mention flock-based locking

---

## Phase 3 – Domain Migration

Migrate one domain at a time. Each must render → validate → deploy → health-check.

---

### Stage 3.1 – GitLab Domain

- [ ] Create `domains/gitlab/metadata.yml` with ports, relationships, and network strategy:
  ```yaml
  domain: gitlab
  requires: []
  exports:
    ports:
      http: 8080
      https: 443
      ssh: 2222
      metrics: 9152
    endpoints:
      web: https://gitlab.{DOMAIN}
      metrics: http://gitlab:9152/metrics
  networks:
    internal: true
    external: false
  ```
- [ ] Convert `pi-forge/legacy/compose/gitlab.yml` → `domains/gitlab/templates/compose.yml.tmpl`.
- [ ] Move tuned `pi-forge/legacy/config/gitlab.rb.template` → `domains/gitlab/templates/gitlab.rb.tmpl`.
- [ ] Add `.required.env` listing required variables.
- [ ] Render + deploy:
  ```bash
  make render DOMAIN=gitlab
  make validate
  make deploy DOMAIN=gitlab
  ```
- [ ] Verify:
  - [ ] Web UI reachable at `https://gitlab.{DOMAIN}`.
  - [ ] SSH clone works on port 2222.
  - [ ] Metrics endpoint `/metrics` returns data.
  - [ ] Health check passes: `curl -f https://gitlab.{DOMAIN}/-/health`.

---

### Stage 3.2 – Monitoring Domain

- [ ] Create `domains/monitoring/metadata.yml` with relationships:
  ```yaml
  domain: monitoring
  requires: []
  exports:
    ports:
      prometheus: 9090
      grafana: 3000
      loki: 3100
  networks:
    internal: true
    external: false
  ```
- [ ] Move/convert from legacy:
  - `pi-forge/legacy/compose/monitoring.yml` → `domains/monitoring/templates/compose.yml.tmpl`
  - `pi-forge/legacy/config/prometheus.yml` → `domains/monitoring/templates/prometheus.yml.tmpl`
  - `pi-forge/legacy/config/alertmanager.yml` → `domains/monitoring/templates/alertmanager.yml.tmpl`
  - `pi-forge/legacy/config/loki.yml` → `domains/monitoring/templates/loki.yml.tmpl`
  - `pi-forge/legacy/config/grafana-datasource.yml` → `domains/monitoring/templates/grafana-datasource.yml.tmpl`
- [ ] Update volume paths to `/srv/monitoring/config` and `/srv/monitoring/data`.
- [ ] Fresh start (remove existing data):
  ```bash
  sudo rm -rf /srv/prometheus/data/* /srv/grafana/data/* /srv/loki/data/*
  ```
- [ ] Render + deploy:
  ```bash
  make render DOMAIN=monitoring
  make deploy DOMAIN=monitoring
  ```
- [ ] Confirm Prometheus scrapes GitLab metrics successfully.

---

### Stage 3.3 – Tunnel & Adblocker

- [ ] Create `domains/tunnel/metadata.yml`:
  ```yaml
  domain: tunnel
  requires: []
  exports:
    ports: {}
  networks:
    internal: false
    external: true
  ```
- [ ] Document Cloudflare Tunnel dashboard settings in `domains/tunnel/README.md`:
  ```markdown
  ## Cloudflare Tunnel Configuration
  - Service: https://127.0.0.1:443
  - Origin Request: noTLSVerify: true
  - SSL/TLS: Full (strict)
  - Routes: gitlab.{DOMAIN}, registry.{DOMAIN}, grafana.{DOMAIN}
  ```
- [ ] Create `domains/adblocker/metadata.yml` and move `pi-forge/legacy/config/unbound.conf`.
- [ ] Render + deploy each:
  ```bash
  make render DOMAIN=tunnel
  make deploy DOMAIN=tunnel
  make render DOMAIN=adblocker
  make deploy DOMAIN=adblocker
  ```
- [ ] Confirm DNS queries and tunnels work.

---

## Phase 4 – Validation & Manifest

**Goal:** Add self-auditing tools and drift detection.

- [ ] Implement `common/validate.sh`:
  - [ ] Port conflict detection across domains
  - [ ] Dependency validation (no circular deps)
  - [ ] Required environment variables check
- [ ] Implement `common/generate-manifest.sh`:
  - [ ] Docker image digests and tags
  - [ ] Config file checksums
  - [ ] Git commit hash
- [ ] Implement `common/validate-deps.sh` for circular dependency detection.
- [ ] Add configuration drift detection:
  ```bash
  # Compare running containers vs rendered configs
  docker inspect <container> | jq '.[0].Config.Env' > running.env
  diff running.env generated/<domain>/.env
  ```
- [ ] Run validation:
  ```bash
  make validate
  make manifest
  git diff MANIFEST.md
  ```
- [ ] Test drift detection by modifying a template and re-rendering.

---

## Phase 5 – Infrastructure (IaC)

**Goal:** Separate cloud resources cleanly with fresh state.

- [ ] Move `pi-forge/legacy/terraform/` to `infra/terraform/`.
- [ ] Split modules: `aws/`, `gcp/`, `cloudflare/`.
- [ ] Update variable names to match `config-registry/env/base.env`.
- [ ] Start with clean Terraform state:
  ```bash
  cd infra/terraform
  rm -rf .terraform/ terraform.tfstate*
  terraform init
  terraform plan
  ```
- [ ] Test:
  ```bash
  cd infra/terraform
  terraform init
  terraform plan
  ```
- [ ] Add make targets:
  - [ ] `make terraform-apply`
  - [ ] `make terraform-destroy`

---

## Phase 6 – Backup & Disaster Recovery

**Goal:** Unified backup layer with domain registration.

- [ ] Create `backup/policy.yml` defining paths + retention:
  ```yaml
  retention:
    daily: 7d
    weekly: 4w
    monthly: 12m
  ```
- [ ] Write scripts:
  - [ ] `backup/scripts/backup.sh`
  - [ ] `backup/scripts/restore.sh`
  - [ ] `backup/scripts/verify.sh`
- [ ] Add backup registration to domain metadata:
  ```yaml
  # domains/gitlab/metadata.yml
  backup:
    paths:
      - /srv/gitlab/data
    frequency: daily
    retention: 7d
  ```
- [ ] Hook per-domain backups (`domains/<domain>/scripts/backup.sh`).
- [ ] Test restore to separate directory:
  ```bash
  make backup DOMAIN=gitlab
  make restore DOMAIN=gitlab DEST=/tmp/test-restore
  ```

---

## Phase 7 – Testing & Observability

**Goal:** Final polish and reliability checks with health check standardization.

- [ ] Add `ci/lint-metadata.sh` to verify schema keys exist.
- [ ] Add `ci/compose-dryrun.sh` to check syntax:
  ```bash
  docker compose -f generated/<domain>/compose.yml config
  ```
- [ ] Add `ci/smoke.sh` for basic health probes.
- [ ] Standardize health check patterns across domains:
  ```yaml
  # domains/*/metadata.yml
  health_checks:
    - endpoint: /-/health
      timeout: 5s
    - endpoint: /metrics
      timeout: 2s
  ```
- [ ] Hook CI scripts into `make validate`.
- [ ] Extend Prometheus:
  - [ ] Generate `generated/metrics/build_info.prom` each render:
    ```bash
    echo "build_info{git_commit=\"$(git rev-parse --short HEAD)\"} 1" \
      > generated/metrics/build_info.prom
    ```
  - [ ] Add dashboard for service health.
- [ ] Document operational commands in `docs/OPERATIONS.md`.

---

## Phase 8 – Finalization

- [ ] Run full cycle:
  ```bash
  make render DOMAIN=gitlab
  make deploy DOMAIN=gitlab
  make render DOMAIN=monitoring
  make deploy DOMAIN=monitoring
  make validate
  make manifest
  ```
- [ ] Confirm all manifests and ports are consistent.
- [ ] Clean up `pi-forge/legacy/`.
- [ ] Commit and tag:
  ```bash
  git add .
  git commit -m "Refactored into domain-driven structure"
  git tag v2.0.0
  ```

---

### Misc

- [ ] Add Ansible Vault integration to decrypt `secrets.env.vault`.
- [ ] Add Slack / Email alert on manifest drift.
- [ ] Add scheduled nightly backup job via cron or systemd timer.
- [ ] Explore multi-host orchestration (e.g. swarm or k3s) later.

---

**End state:**
Reproducible, domain-driven setup with clear separation of concerns, version-locked artifacts, and fully automatable recovery.
