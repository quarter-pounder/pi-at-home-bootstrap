# Rebuild Steps

## Phase 0 – Preparation (complete)
- Legacy stack archived under `000-legacy` with tags and backups
- New directory skeleton initialised; `/srv` snapshot captured

## Phase 1 – Bootstrap (complete)
- Host bootstrap scripts hardened (`01-preflight.sh` → `05-verify.sh`)
- Docker tuned for Raspberry Pi (overlay2, log rotation, live-restore)

## Phase 2 – Configuration Registry (complete)
- `config-registry/env/` populated with base variables, domains, and ports
- JSON schemas and `make validate` guardrails in place
- `metadata.py`, `render_config.py`, and watchdog scripts operational

## Phase 3 – Domain Migration (complete)
- Forgejo, PostgreSQL, Woodpecker, runner, registry, tunnel, adblocker deployed via generated Compose stacks
- Monitoring domain consolidated with Grafana dashboards (services-overview, runners-overview)
- Alert suppression system for manually downed services
- Pi telemetry collection (temperature, voltage, throttling) via host-side cron
- cAdvisor memory metrics enabled and working
- Alertmanager webhook configuration fixed
- All Prometheus targets scraping successfully
- Loki log aggregation functional

## Phase 4 – Operations Hardening (complete)
- Backup system implemented with restic, declarative backup.yml profiles, and .pgpass support
- GitHub Actions runner management with multi-runner support via make targets
- Alert suppression markers for runners and Woodpecker server
- SMTP configuration in place (requires testing)
- Cloud backup infrastructure ready (requires RESTIC_REMOTE configuration)
- Disaster recovery scope defined (Forgejo + Actions runner focus)
