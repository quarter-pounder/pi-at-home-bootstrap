# Woodpecker Domain

Woodpecker provides lightweight CI/CD for Forgejo repositories. The server relies on PostgreSQL and authenticates users via Forgejo OAuth.

## Contract
- **Inputs**
  - Rendered Compose file (`domains/woodpecker/templates/compose.yml.tmpl`)
  - Environment values (`WOODPECKER_*`, database credentials, Forgejo OAuth keys)
- **Outputs**
  - Web UI / API on `PORT_WOODPECKER_HTTP`
  - Prometheus metrics on `PORT_WOODPECKER_METRICS`
- **State**: `/srv/woodpecker/server`
- **Lifecycle**: `make deploy DOMAIN=woodpecker`
- **Relationships**
  - `placement: tunnel`
  - `requires: [forgejo, postgres]`
  - `exposes_to: [tunnel, monitoring]`
  - `consumes: [forgejo, postgres]`

## Runner Domain
- The `woodpecker-runner` domain hosts the Docker runner.
- Shared secret (`WOODPECKER_AGENT_SECRET`) lives in the vault and must match between server and runner.
- Runner attaches to the same `forgejo-network` bridge to reach the server.
- Authenticate against GHCR before pulling the official images: `docker login ghcr.io` (GitHub PAT with `read:packages`).

## OAuth Setup
1. Create a Forgejo OAuth application with callback `${WOODPECKER_HOST}/authorize`.
2. Store the generated client ID/secret in the vault (`WOODPECKER_FORGEJO_CLIENT_ID`, `WOODPECKER_FORGEJO_CLIENT_SECRET`).
3. Populate `WOODPECKER_ADMIN_USERS` with the Forgejo usernames allowed to administer Woodpecker.

## Metrics & Alerts
- Prometheus scrapes the metrics endpoint on `PORT_WOODPECKER_METRICS`.
- Alerting rules monitor for `woodpecker` job uptime.

## Backups
- Woodpecker stores build metadata in PostgreSQL; include the `woodpecker` database in backups.
- Pipelines and secrets live in the server volume (`/srv/woodpecker/server`).

