# Rebuild Plan

## Architecture Snapshot
- **Bootstrap (tier 0):** bash scripts in `bootstrap/` ready the Pi host and Docker; this layer is complete and unchanged since the initial rebuild.
- **Config registry (tier 1):** `config-registry/` captures declarative intent (`env/`), validation rules (`schema/`), and ephemeral renders (`state/`). `metadata.py` materialises cache files, and canonical `domains/*/metadata.yml` stay under version control.
- **Domains (tier 2):** each service (`forgejo`, `postgres`, `woodpecker`, runner, `monitoring`, `adblocker`, `registry`, `tunnel`) owns its templates plus metadata. `generated/<domain>/` is rendered on demand and never committed.
- **Common tooling:** `common/Makefile`, `render_config.py`, `validate.sh`, and `tools/metadata_watchdog.py` enforce the configuration pipeline and drift monitoring.

## Progress Snapshot
- [x] Host bootstrap pipeline verified on Raspberry Pi
- [x] Config registry schemas, metadata generation, and render workflow
- [x] Forgejo, PostgreSQL, Woodpecker, runner, registry, and tunnel domains migrated
- [x] Monitoring domain rebuilt; Alloy/Loki log ingestion stabilised; dashboards consolidated
- [x] Adblocker domain switched to ARM-compatible images and health-checked
- [ ] Monitoring polish: log severity mapping, alert review, SMTP integration
- [ ] Disaster recovery design for Forgejo + Forejo Actions Runnrt
      (lightweight cloud target, Cloud Run with externel PostgereSQL should suffice)
- [ ] Optional Terraform and remote-backup automation
      (defer until monitoring soak completes)

## Working Principles

- **Single source of truth:**
  Edit `config-registry/env/{base.env,domains.yml,ports.yml}` →
  run `make generate-metadata` →
  review metadata-cache diff vs `domains/*/metadata.yml` →
  commit via `make commit-metadata`.

- **Layered environments:**
  Renderer loads `base.env` → `overrides/<env>.env` → decrypted `secrets.env.vault`.
  Templates receive both environment variables and structured context.

- **Immutable vs mutable:**
  Templates, metadata, and manifests live in git; runtime state lives under `/srv/<domain>/` and is captured through restic.

- **Validation gates:**
  `make validate` for structural checks,
  `make validate-schema` for schema enforcement,
  `metadata_watchdog.py` for live drift detection.

- **Deployment loop:**
  `make render DOMAIN=<name>` → inspect `generated/<name>/` →
  `make deploy DOMAIN=<name>` → verify in dashboards/logs.

## Immediate Next Steps
1. Let the monitoring stack run for several days to confirm which alerts and log panels are useful.
2. Map Docker `stream` to a `level` label in Alloy, adjust Grafana panels, and introduce SMTP once alert requirements are known.
3. Produce a scoped DR plan for Forgejo (data replication plus rapid container bring-up using NeonDB, cloud storage, and Cloud Run as candidates).
4. Revisit Terraform modules and remote backup targets after the monitoring soak and DR design settle.
