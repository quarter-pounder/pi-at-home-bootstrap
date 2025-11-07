.PHONY: env generate-metadata commit-metadata diff-metadata metadata-check render deploy destroy validate validate-schema manifest help drift-check
.DEFAULT_GOAL := help
.SILENT:

ENV ?= dev
DOMAIN ?= gitlab
ROOT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))/..
export ROOT_DIR
METADATA_BIN := $(ROOT_DIR)/common/lib/metadata.sh

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
	@echo "  make deploy DOMAIN=<name>       - Deploy domain"
	@echo "  make destroy DOMAIN=<name>      - Destroy domain"
	@echo "  make manifest                   - Generate manifest"
	@echo "  make drift-check                - Fail CI if metadata drift detected"

env:
	@echo "[Env] Loading environment $(ENV)"
	@cd $(ROOT_DIR) && set -a && source config-registry/env/base.env && set +a

generate-metadata:
	@cd $(ROOT_DIR) && NO_CACHE=1 $(METADATA_BIN) generate

commit-metadata:
	@cd $(ROOT_DIR) && $(METADATA_BIN) commit

diff-metadata:
	@cd $(ROOT_DIR) && $(METADATA_BIN) diff

metadata-check:
	@cd $(ROOT_DIR) && $(METADATA_BIN) check

drift-check: metadata-check
	@if [ $$? -eq 0 ]; then \
		echo "[CI] Metadata drift check passed"; \
	else \
		echo "[CI] Metadata drift detected — please run 'make diff-metadata' locally"; \
		exit 1; \
	fi

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
	@cd $(ROOT_DIR) && bash common/render-config.sh $(DOMAIN) $(ENV)

deploy: render
	@echo "[Deploy] $(DOMAIN)"
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml up -d

destroy:
	@echo "[Destroy] $(DOMAIN)"
	@cd $(ROOT_DIR) && docker compose -f generated/$(DOMAIN)/compose.yml down -v

manifest:
	@echo "[Manifest] Generating manifest..."
	@cd $(ROOT_DIR) && bash common/generate-manifest.sh || echo "Manifest generation not yet implemented"
