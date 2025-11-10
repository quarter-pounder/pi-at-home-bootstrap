export ANSIBLE_VAULT_PASSWORD_FILE := $(VAULT_PASS)
.ONESHELL:
.SILENT:
.DEFAULT_GOAL := help

ENV ?= dev
DOMAIN ?= gitlab
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))/..
export ROOT_DIR
PYTHON ?= python3
METADATA_SCRIPT := $(ROOT_DIR)/common/metadata.py
VAULT_FILE := $(ROOT_DIR)/config-registry/env/secrets.env.vault
VAULT_PASS := $(ROOT_DIR)/.vault_pass

help:
	@echo "Available targets:"
	@echo "  make env ENV=<env>              - Load environment variables"
	@echo "  make generate-metadata          - Generate metadata cache files"
	@echo "  make diff-metadata              - Check for metadata drift"
	@echo "  make commit-metadata            - Review and commit metadata changes"
	@echo "  make metadata-check             - Generate metadata and fail on drift"
	@echo "  make validate                   - Runtime validation (fast, minimal)"
	@echo "  make validate-schema            - Schema validation (CI enforcement)"
	@echo "  make render DOMAIN=<name> ENV=<env> - Render templates"
	@echo "    (set DRY_RUN=1 to print available context keys without writing files)"
	@echo "  make deploy DOMAIN=<name>       - Deploy domain"
	@echo "  make destroy DOMAIN=<name>      - Destroy domain"
	@echo "  make manifest                   - Generate manifest"
	@echo "  make drift-check                - Fail CI if metadata drift detected"
	@echo "  make vault-create               - Create secrets.env.vault (uses .vault_pass when present)"
	@echo "  make vault-edit                 - Edit secrets.env.vault"
	@echo "  make vault-view                 - View secrets.env.vault contents"

env:
	@echo "[Env] Loading environment $(ENV)"
	@cd $(ROOT_DIR) && set -a && source config-registry/env/base.env && set +a

generate-metadata:
	@cd $(ROOT_DIR) && $(PYTHON) $(METADATA_SCRIPT) generate

commit-metadata:
	@cd $(ROOT_DIR) && $(PYTHON) $(METADATA_SCRIPT) commit

diff-metadata:
	@cd $(ROOT_DIR) && $(PYTHON) $(METADATA_SCRIPT) diff

metadata-check:
	@cd $(ROOT_DIR) && $(PYTHON) $(METADATA_SCRIPT) check

drift-check:
	@cd $(ROOT_DIR) && $(PYTHON) $(METADATA_SCRIPT) check || ( \
		echo "[CI] Metadata drift detected — run 'make diff-metadata' locally" && exit 1)
	@echo "[CI] Metadata drift check passed"

validate: metadata-check
	@cd $(ROOT_DIR) && bash common/validate.sh

lint: validate
	@echo "[Lint] Validation completed"

validate-schema:
	@echo "[Validate] Schema validation (CI enforcement)"
	@cd $(ROOT_DIR) && \
	if ! command -v ajv >/dev/null 2>&1; then \
		echo "[WARN] ajv not found — skipping schema validation"; \
		echo "Install: npm install -g ajv-cli"; \
		exit 0; \
	fi; \
	for schema in domains ports; do \
		yq -o=json config-registry/env/$${schema}.yml | \
		ajv validate -s config-registry/schema/$${schema}.schema.yml || exit 1; \
	done

render: validate
	@echo "[Render] $(DOMAIN) for $(ENV)"
	@cd $(ROOT_DIR) && $(PYTHON) common/render_config.py --domain $(DOMAIN) --env $(ENV) $(if $(DRY_RUN),--dry-run)

deploy: render
	@echo "[Deploy] $(DOMAIN)"
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml up -d

destroy:
	@echo "[Destroy] $(DOMAIN)"
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml down -v

manifest:
	@echo "[Manifest] Generating manifest..."
	@cd $(ROOT_DIR) && bash common/generate-manifest.sh || echo "Manifest generation not yet implemented"

vault-create:
	@cd $(ROOT_DIR) && \
	if ! command -v ansible-vault >/dev/null 2>&1; then \
		echo "[Vault][err] ansible-vault not installed"; exit 1; \
	fi; \
	if [[ -f config-registry/env/secrets.env.vault ]]; then \
		echo "[Vault][warn] secrets.env.vault already exists"; exit 1; \
	fi; \
	if [[ -f .vault_pass ]]; then \
		ansible-vault create config-registry/env/secrets.env.vault --vault-password-file .vault_pass; \
	else \
		ansible-vault create config-registry/env/secrets.env.vault; \
	fi

vault-edit:
	@cd $(ROOT_DIR) && \
	if ! command -v ansible-vault >/dev/null 2>&1; then \
		echo "[Vault][err] ansible-vault not installed"; exit 1; \
	fi; \
	if [[ ! -f config-registry/env/secrets.env.vault ]]; then \
		echo "[Vault][err] secrets.env.vault missing"; exit 1; \
	fi; \
	if [[ -f .vault_pass ]]; then \
		ansible-vault edit config-registry/env/secrets.env.vault --vault-password-file .vault_pass; \
	else \
		ansible-vault edit config-registry/env/secrets.env.vault; \
	fi

vault-view:
	@cd $(ROOT_DIR) && \
	if ! command -v ansible-vault >/dev/null 2>&1; then \
		echo "[Vault][err] ansible-vault not installed"; exit 1; \
	fi; \
	if [[ ! -f config-registry/env/secrets.env.vault ]]; then \
		echo "[Vault][err] secrets.env.vault missing"; exit 1; \
	fi; \
	if [[ -f .vault_pass ]]; then \
		ansible-vault view config-registry/env/secrets.env.vault --vault-password-file .vault_pass; \
	else \
		ansible-vault view config-registry/env/secrets.env.vault; \
	fi

check-secrets:
	@cd $(ROOT_DIR) && \
	if [[ ! -f $(VAULT_FILE) ]]; then \
		echo "[Vault][warn] $(VAULT_FILE) missing — templates may lack secrets"; \
	fi; \
	if [[ ! -s $(VAULT_PASS) ]]; then \
		echo "[Vault][warn] $(VAULT_PASS) missing or empty"; \
	fi
