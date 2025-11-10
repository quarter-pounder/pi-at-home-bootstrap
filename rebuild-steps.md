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
- [ ] Create `config-registry/env/secrets.env.vault` with ansible-vault (`docs/operations/secrets.md`):
  ```bash
  openssl rand -base64 48 > .vault_pass
  chmod 600 .vault_pass
  ansible-vault create config-registry/env/secrets.env.vault
  # Add: GITLAB_ROOT_PASSWORD, GRAFANA_ADMIN_PASSWORD, SMTP_PASSWORD, etc.
  ```
- [x] Create `config-registry/env/overrides/` directory:
  - [ ] `dev.env` - Development environment overrides
  - [ ] `staging.env` - Staging environment overrides
  - [ ] `prod.env` - Production environment overrides

### 2.3 – Declarative Configuration

- [x] Create `config-registry/env/ports.yml` with port assignments:
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

- [x] Create `config-registry/env/domains.yml`:
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
- [x] Create `config-registry/schema/domains.schema.yml`:
  - Domain structure validation
  - Placement / requires / exposes validation
- [x] Create `config-registry/schema/ports.schema.yml`:
  - Enforces naming convention: `{domain: {port_name: number}}`
  - Port conflict detection rules

### 2.5 – Metadata Generation

- [x] Implement Python metadata CLI (`common/metadata.py`):
  - Reads `domains.yml` and `ports.yml`
  - Merges port assignments into domain definitions
  - Generates `_meta` field with `generated_at`, `source_hash`, `domain`
  - Outputs to `config-registry/state/metadata-cache/*.yml`
  - Uses atomic file writes (temp file + cmp + mv)

### 2.6 – Validation Scripts

- [x] Implement `common/validate.sh` (runtime - fast, minimal):
  - Fast YAML syntax checks with `yq`
  - Port conflict detection
  - Basic structural validation
  - No external dependencies (bash/yq only)

- [x] Add `validate-schema` target to `common/Makefile`:
  - Full JSON Schema validation with `ajv` (CI enforcement)
  - Validates `domains.yml` and `ports.yml` against schemas
  - Requires Node.js/ajv (CI environment)

### 2.7 – Makefile Targets

- [x] Create `common/Makefile` with targets:
  - `make generate-metadata` - Creates `state/metadata-cache/*.yml`
  - `make diff-metadata` - Checks for drift (exits 1 if drift found)
  - `make commit-metadata` - Reviews diffs and copies to `domains/*/metadata.yml`
  - `make validate` - Runtime validation (fast, minimal)
  - `make validate-schema` - Schema validation (CI enforcement)
  - `make render DOMAIN=<name> ENV=<env>` - Renders templates
  - `make deploy DOMAIN=<name>` - Deploys domain
  - `make env ENV=<env>` - Loads environment variables

### 2.8 – Configuration Rendering

- [x] Implement Python-based renderer (`common/render_config.py`):
  - Layered environment loading: `base.env` → `overrides/<env>.env` → `secrets.env`
  - Decrypts `secrets.env.vault` only during render (temporary in-memory view via `ansible-vault view`)
  - Loads `ports.yml` as both structured data and `PORT_*` env-style variables
  - Renders Jinja2 templates from `domains/<domain>/templates/` to `generated/<domain>/`
  - Declare dependencies in `requirements/render.txt` (install via `pip install -r requirements/render.txt` or apt packages `python3-jinja2`, `python3-yaml`)

### 2.9 – Git Configuration

- [x] Update `.gitignore`:
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
  - Declarative flow: `domains.yml` + `ports.yml` → `metadata.py generate` → `metadata.yml`
  - State directory purpose (ephemeral vs versioned)
  - Port naming convention and conversion
  - Two-tier validation approach

### 2.12 – Makefile & Validation Hardening

- [x] Move Makefile inline shell into `common/lib/*.sh` helpers
  - [x] Implement `metadata_diff`, `metadata_commit`, `load_env` helpers
  - [x] Source helpers in Make targets
- [x] Introduce composite target `metadata-check` (`make generate-metadata && make diff-metadata`)
- [ ] Extend `common/validate.sh`
  - [ ] Fail if Docker images use `:latest` or omit tags in templates/metadata
  - [ ] Fail if Terraform providers lack explicit version pins / lockfile
  - [ ] Ensure metadata `_meta` includes `git_commit` / `source_hash`

### 2.13 – Metadata Watchdog

- [x] Create `tools/metadata_watchdog.py` (Python) to monitor `config-registry/state/metadata-cache/`
  - [x] Watch for file changes (watchdog/inotify), debounce events
  - [x] Compare cache vs `domains/<name>/metadata.yml`
  - [x] Log warning (and optional diff) when drift detected
  - [x] Support `--auto-diff` to run `make diff-metadata`
- [x] Add requirements entry (e.g., `requirements/watchdog.txt`)
- [x] Document usage in `docs/tools/metadata-watchdog.md`
  - [x] Describe systemd unit example
  - [ ] Mention flock-based locking

---

## Phase 3 – Domain Migration

Migrate one domain at a time. Each must render → validate → deploy → health-check.

---

### Stage 3.1 – GitLab Domain

- [x] Create `domains/gitlab/metadata.yml` with ports, relationships, and network strategy:
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
- [x] Convert `pi-forge/legacy/compose/gitlab.yml` → `domains/gitlab/templates/compose.yml.tmpl`.
- [x] Move tuned `pi-forge/legacy/config/gitlab.rb.template` → `domains/gitlab/templates/gitlab.rb.tmpl`.
- [ ] Add `.required.env` listing required variables.
- [ ] Render + deploy:
  ```bash
  make render DOMAIN=gitlab
  make validate
  make deploy DOMAIN=gitlab
  ```
