# GitLab Domain

GitLab CE is operated as a sealed appliance. The new config-registry renders the inputs it needs and Compose manages its lifecycle. No manual mutation inside the running container.

## Contract
- **Inputs**
  - Rendered `domains/gitlab/templates/gitlab.rb.tmpl` → `/etc/gitlab/gitlab.rb`
  - Environment variables exported during render (`PORT_GITLAB_*`, SMTP, backups, etc.)
- **Outputs**
  - HTTP(S) endpoint (ports defined in `config-registry/env/ports.yml`)
  - SSH endpoint for Git/SSH access
  - Metrics endpoint scraped by Prometheus (GitLab workhorse exporter)
- **State**: `/srv/gitlab/{config,data,logs}`
- **Lifecycle**: `docker compose up/down`, plus scripted backup/restore
- **Relationships** (as captured in `domains.yml`):
  - `placement: tunnel`
  - `requires: []`
  - `exposes_to: [tunnel, monitoring, registry]`
  - `consumes: []`

## Configuration Flow
1. Edit declarative inputs (`env/base.env`, `env/ports.yml`, `domains.yml`).
2. `make generate-metadata` → review drift → commit `domains/gitlab/metadata.yml`.
3. `make render DOMAIN=gitlab ENV=<env>` → produces `generated/gitlab/{compose.yml,gitlab.rb,...}`.
4. Deploy with `make deploy DOMAIN=gitlab`.

## Registry Integration
- External registry container lives in the `registry` domain and shares the `gitlab-shared` Docker network.
- `REGISTRY_DOMAIN`, `REGISTRY_EXTERNAL_URL`, and `REGISTRY_API_URL` feed `gitlab.rb.tmpl` to point GitLab at the standalone registry (`registry` must be reachable as `gitlab-registry:5000` on the shared network).
- Set `REGISTRY_HTTP_SECRET` (ideally in `secrets.env.vault`) before rendering; this value seeds the registry token service.
- `gitlab_rails['registry_enabled']` stays on, while the in-container registry service remains disabled—GitLab proxies to the dedicated registry domain instead.
- Vault workflow reference: `docs/operations/secrets.md`

## Templates
- `domains/gitlab/templates/compose.yml.tmpl`
  - Publishes only the ports declared in metadata
  - Mounts `/srv/gitlab/{config,data,logs}`
  - Attaches to an internal bridge network plus external ingress (tunnel)
  - Rendered via Jinja2 with env variables (`GITLAB_*`, `PORT_GITLAB_*`, etc.)
- `domains/gitlab/templates/gitlab.rb.tmpl`
  - Sets `external_url`, SMTP, backup options
  - Disables embedded Prometheus/Alertmanager exporters
  - Configures workhorse metrics listener on `PORT_GITLAB_METRICS`

## Networking
- GitLab runs on an internal Docker network (e.g. `gitlab-network`).
- External exposure is handled by the ingress/tunnel service.
- Other domains use service name + internal ports; GitLab never talks directly to the Internet.

## Backups & Restore
- Nightly job (outside container): `docker exec gitlab gitlab-rake gitlab:backup:create`
- Sync artifacts to cloud storage (include `/srv/gitlab/config/gitlab-secrets.json` and `/srv/gitlab/config/ssl` if used)
- Restore playbook: provision fresh container → mount `/srv/gitlab` → restore from backup

## Observability
- Prometheus scrapes `http://gitlab:PORT_GITLAB_METRICS/-/metrics`
- Health checks use external endpoints (HTTP `/-/health`, SSH smoke test)
- No direct access to internal Omnibus exporters

Keep the domain metadata concise: placement, `requires/exposes_to/consumes`, expected ports, and exported metrics. Anything inside the Omnibus stack (Redis, Sidekiq, Gitaly) remains opaque.

Reminder: recording the relationships may feel excessive, but it prevents forgetting which services (monitoring, tunnel, registry) depend on GitLab signals later.

## Failure Modes
- **Disk full:** backups or logs exceed `/srv/gitlab` capacity → container restarts; mitigation: rotate logs, enforce quotas.
- **Database corruption:** recover from latest `gitlab:backup:create`.
- **Tunnel outage:** GitLab remains reachable locally via Docker network.
