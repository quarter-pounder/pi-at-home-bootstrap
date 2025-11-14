.ONESHELL:
.SILENT:
.DEFAULT_GOAL := help

.PHONY: help env generate-metadata commit-metadata diff-metadata metadata-check drift-check validate lint validate-schema render deploy destroy manifest vault-create vault-edit vault-view check-secrets status

ENV ?= dev
DOMAIN ?= forgejo
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))/..
export ROOT_DIR
PYTHON ?= python3
METADATA_SCRIPT := $(ROOT_DIR)/common/metadata.py
VAULT_FILE := $(ROOT_DIR)/config-registry/env/secrets.env.vault
VAULT_PASS := $(ROOT_DIR)/.vault_pass

BACKUP_SCRIPT := $(ROOT_DIR)/common/scripts/backup.sh
BACKUP_ENV := PIHOLE_API_TOKEN

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
	@echo "    (set FORCE_RECREATE=1 to force container recreation)"
	@echo "  make destroy DOMAIN=<name>      - Destroy domain"
	@echo "  make manifest                   - Generate manifest"
	@echo "  make drift-check                - Fail CI if metadata drift detected"
	@echo "  make vault-create               - Create secrets.env.vault (uses .vault_pass when present)"
	@echo "  make vault-edit                 - Edit secrets.env.vault"
	@echo "  make vault-view                 - View secrets.env.vault contents"

env:
	@echo "[Env] Loading environment $(ENV)"
	@if [ ! -f "$(ROOT_DIR)/.env" ]; then \
		echo "[Env][info] .env not found; copy config-registry/env/base.env to .env and customize it"; \
		exit 1; \
	fi
	@cd $(ROOT_DIR) && set -a && source config-registry/env/base.env && source .env && set +a

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
	for schema in $(basename $(wildcard config-registry/schema/*.schema.yml)); do \
		yq -o=json config-registry/env/$${schema}.yml | \
		ajv validate -s config-registry/schema/$${schema}.schema.yml || exit 1; \
	done

render: validate
	@echo "[Render] $(DOMAIN) for $(ENV)"
	@if [ ! -f "$(ROOT_DIR)/.env" ]; then \
		echo "[Render][err] .env not found; copy config-registry/env/base.env to .env and customize it"; \
		exit 1; \
	fi
	@cd $(ROOT_DIR) && $(PYTHON) common/render_config.py --domain $(DOMAIN) --env $(ENV) $(if $(DRY_RUN),--dry-run)

deploy: render
	@echo "[Deploy] $(DOMAIN)"
	@[ -f "$(ROOT_DIR)/generated/$(DOMAIN)/compose.yml" ] || { echo "[Deploy][err] compose.yml not found for $(DOMAIN)"; exit 1; }
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml up -d --pull always $(if $(FORCE_RECREATE),--force-recreate)

destroy:
	@echo "[Destroy] $(DOMAIN)"
	@[ -f "$(ROOT_DIR)/generated/$(DOMAIN)/compose.yml" ] || { echo "[Destroy][err] compose.yml not found for $(DOMAIN)"; exit 1; }
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml down -v

manifest:
	@echo "[Manifest] Generating manifest..."
	@cd $(ROOT_DIR) && bash common/generate-manifest.sh || echo "Manifest generation not yet implemented"

define VAULT_CMD
	@cd $(ROOT_DIR) && \
	if ! command -v ansible-vault >/dev/null 2>&1; then \
		echo "[Vault][err] ansible-vault not installed"; exit 1; \
	fi; \
	if [ ! -f config-registry/env/secrets.env.vault ]; then \
		echo "[Vault][err] secrets.env.vault missing"; exit 1; \
	fi
endef

vault-create:
	@cd $(ROOT_DIR) && \
	if ! command -v ansible-vault >/dev/null 2>&1; then \
		echo "[Vault][err] ansible-vault not installed"; exit 1; \
	fi; \
	if [ -f config-registry/env/secrets.env.vault ]; then \
		echo "[Vault][warn] secrets.env.vault already exists"; exit 1; \
	fi; \
	if [ -f .vault_pass ]; then \
		ansible-vault create config-registry/env/secrets.env.vault --vault-password-file .vault_pass; \
	else \
		ansible-vault create config-registry/env/secrets.env.vault; \
	fi

vault-edit:
	$(VAULT_CMD)
	@cd $(ROOT_DIR) && \
	if [ -f .vault_pass ]; then \
		ansible-vault edit config-registry/env/secrets.env.vault --vault-password-file .vault_pass; \
	else \
		ansible-vault edit config-registry/env/secrets.env.vault; \
	fi

vault-view:
	$(VAULT_CMD)
	@cd $(ROOT_DIR) && \
	if [ -f .vault_pass ]; then \
		ansible-vault view config-registry/env/secrets.env.vault --vault-password-file .vault_pass; \
	else \
		ansible-vault view config-registry/env/secrets.env.vault; \
	fi

check-secrets:
	@cd $(ROOT_DIR) && \
	missing=0; \
	if [ ! -f "$(VAULT_FILE)" ]; then \
		echo "[Vault][warn] $(VAULT_FILE) missing — templates may lack secrets"; \
		missing=1; \
	fi; \
	if [ -f "$(VAULT_PASS)" ]; then \
		if [ ! -s "$(VAULT_PASS)" ]; then \
			echo "[Vault][warn] $(VAULT_PASS) exists but is empty"; \
			missing=1; \
		fi; \
	else \
		echo "[Vault][info] .vault_pass not found — ansible-vault will prompt interactively"; \
	fi; \
	if [ $$missing -eq 0 ]; then \
		echo "[Vault][ok] secrets vault ready"; \
	fi

status:
	@echo "[Status] Metadata diff:"
	@$(MAKE) -s diff-metadata || true
	@$(MAKE) -s check-secrets || true
	@echo "[Status] Rendered domains:"
	@ls -1 $(ROOT_DIR)/generated 2>/dev/null || echo "(none)"

.PHONY: backup backup-cloud backup-prune
backup:
	@BACKUP_MODE=${BACKUP_MODE:-manual} bash $(BACKUP_SCRIPT)

backup-prune:
	@BACKUP_MODE=prune BACKUP_PRUNE=1 bash $(BACKUP_SCRIPT)

backup-cloud:
	@if [ -z "$(RESTIC_REMOTE)" ]; then \
		echo "RESTIC_REMOTE not set"; exit 1; \
	fi
	@BACKUP_MODE=cloud RESTIC_REPOSITORY="$(RESTIC_REMOTE)" bash $(BACKUP_SCRIPT)
