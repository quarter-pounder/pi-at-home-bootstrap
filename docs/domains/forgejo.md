# Forgejo Domain

Forgejo replaces the previous GitLab CE deployment. The switch was driven by three constraints:

- GitLab CE does not publish ARM64 images; only `linux/amd64` builds are available (as for now).
- Emulation (QEMU/binfmt) cannot sustain the Omnibus init workload—`gitlab-ctl` triggers heavy Chef/Ruby orchestration that repeatedly crashes under emulation.
- Shipping the LinuxServer GitLab build plus external Redis/PostgreSQL services would re-create Omnibus complexity without first-party support.

Forgejo delivers the core features I need (Git hosting, web UI, container registry integration) with an ARM-native image and a much slimmer operational footprint.

## Contract
- **Inputs**
  - Rendered Compose file (`domains/forgejo/templates/compose.yml.tmpl`)
  - Rendered Forgejo configuration (`domains/forgejo/templates/app.ini.tmpl`)
  - Shared environment values (`FORGEJO_*`, `PORT_FORGEJO_*`, database credentials)
- **Outputs**
  - HTTP service on `PORT_FORGEJO_HTTP`
  - SSH service for Git on `PORT_FORGEJO_SSH`
- **State**: `/srv/forgejo/{data,config,log}`
- **Lifecycle**: `make deploy DOMAIN=forgejo`
- **Relationships** (see `domains.yml`)
  - `placement: tunnel`
  - `requires: [postgres]`
  - `exposes_to: [tunnel, monitoring, woodpecker, registry]`
  - `consumes: [postgres]`

## Configuration Flow
1. Ensure the PostgreSQL domain is deployed first so the `forgejo-network` bridge exists.
2. Generate metadata (`make generate-metadata`) and commit drift.
3. Render Forgejo assets (`make render DOMAIN=forgejo ENV=<env>`).
4. Deploy with `make deploy DOMAIN=forgejo`.

### Prerequisites
- Create the shared Docker network once: `docker network create forgejo-network`
- Pull images directly from Docker Hub (pre-auth not required for public tags)
- Supply `FORGEJO_ADMIN_USERNAME`, `FORGEJO_ADMIN_PASSWORD`, `FORGEJO_ADMIN_EMAIL`, and `FORGEJO_APP_SECRET` via `.env` or vault secrets
- Ensure the PostgreSQL init script grants schema ownership to the Forgejo role (update applied in `domains/postgres/templates/init.sql.tmpl`)

## Templates
- `domains/forgejo/templates/compose.yml.tmpl`
  - Mounts `/srv/forgejo/data` to `/data`
  - Publishes HTTP (`PORT_FORGEJO_HTTP`) and SSH (`PORT_FORGEJO_SSH`) endpoints
  - Attaches to the shared `forgejo-network` bridge used by PostgreSQL, Woodpecker, and the registry
  - Seeds configuration (database, mailer, metrics, admin bootstrap) through environment variables with `FORGEJO__...` prefixes
  - Exposes HTTP internally; TLS is terminated by Cloudflare Tunnel at the edge. Set `FORGEJO_EXTERNAL_URL` to the HTTPS tunnel hostname so generated links use HTTPS.
- `domains/forgejo/templates/app.ini.tmpl`
  - (Optional) reference configuration; runtime settings are driven by environment variables
  - `FORGEJO__security__INSTALL_LOCK=true` must remain in the environment. Writing `INSTALL_LOCK` directly in `app.ini` causes Forgejo to skip the first-run bootstrap on some releases.

## CI Integration
- Woodpecker CI runs as a separate domain against the same PostgreSQL instance.
- Forgejo OAuth credentials (`WOODPECKER_FORGEJO_CLIENT_ID/SECRET`) are stored in `secrets.env.vault`.
- Runner(s) authenticate via a shared agent secret (`WOODPECKER_AGENT_SECRET`).

## Metrics & Logs
- Prometheus scrapes the container directly on `http://forgejo:3000/metrics` using the bearer token defined in `FORGEJO_METRICS_TOKEN` (see monitoring domain).
- Alloy tails `/srv/forgejo/logs` for application events.

## Backups
- Dump PostgreSQL (`forgejo` database) and archive `/srv/forgejo/{data,config}`.
- Store secrets (vault) and OAuth tokens alongside database backups for full recovery.

