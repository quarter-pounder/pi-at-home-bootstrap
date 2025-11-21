# Forgejo Domain

Forgejo replaces the previous GitLab CE deployment. The switch was driven by three practical constraints:

- GitLab CE no longer produces ARM64 images; only `linux/amd64` builds are published.
- Emulation (QEMU/binfmt) cannot handle the Omnibus lifecycle reliably — `gitlab-ctl` launches heavy Chef/Ruby orchestration that keeps crashing under emulated ARM.
- Using the LinuxServer GitLab image plus external Redis/PostgreSQL recreates Omnibus complexity without first-party support, and still offers no ARM-native path forward.

Forgejo provides the capabilities this stack needs: Git hosting, a clean web UI, Actions support, and an integrated container registry, with an ARM native image and a much smaller operational footprint.

---

## Contract

**Inputs**
- Rendered Compose specification (`domains/forgejo/templates/compose.yml.tmpl`)
- Rendered Forgejo configuration (`domains/forgejo/templates/app.ini.tmpl`)
- Shared environment values (`FORGEJO_*`, `PORT_FORGEJO_*`, database credentials)

**Outputs**
- HTTP service on `PORT_FORGEJO_HTTP`
- Git SSH service on `PORT_FORGEJO_SSH`

**State**
- `/srv/forgejo/{data,config,log}`

**Lifecycle**
- `make deploy DOMAIN=forgejo`
- `make destroy DOMAIN=forgejo` (tears down the domain but leaves data intact)

**Relationships**
(Defined in `domains.yml`)
- `placement: tunnel`
- Requires: `postgres`
- Exposes to: `tunnel`, `monitoring`, `woodpecker`, `registry`
- Consumes: `postgres`

## Configuration Flow

1. Deploy **PostgreSQL** first — this creates the `forgejo-network` bridge.
2. Generate metadata:
   ```
   make generate-metadata && make diff-metadata
   ```
3. Commit drift when satisfied:
   ```
   make commit-metadata
   ```
4. Render:
   ```
   make render DOMAIN=forgejo ENV=<env>
   ```
5. Deploy:
   ```
   make deploy DOMAIN=forgejo
   ```
6. Perform post-deployment setup:
   `docs/operations/forgejo-woodpecker-setup.md`

---

### Prerequisites
- PostgreSQL domain must be deployed first (creates `forgejo-network`)
- Environment variables configured in `.env` or `secrets.env.vault`
- For Actions support: `FORGEJO_ACTIONS_RUNNER_TOKEN` must be set

---

## Actions Support

Forgejo Actions is **enabled by default**.
The runner is deployed separately as the `forgejo-actions-runner` domain and talks to Forgejo over the internal Docker network.

### Key Settings
- In `app.ini.tmpl`:
  `ENABLED = true`
- Runner token from:
  `FORGEJO_ACTIONS_RUNNER_TOKEN`
- Runner targets internal service URL:
  `http://forgejo:3000`

---

## Mailer Configuration

The mailer configuration uses current Forgejo settings:

- `SMTP_ADDR` for the SMTP server address
- `PROTOCOL` for the connection protocol (smtp, smtps, smtp+starttls)
- `FORCE_TRUST_SERVER_CERT` for certificate validation
- `FROM` address is automatically set to a valid email format (falls back to `noreply@${DOMAIN}` or `noreply@localhost`)

## Notes
- Forgejo data is stored in `/srv/forgejo/data`
- Container registry integration is configured via `REGISTRY_*` environment variables
- Metrics are exposed at `/metrics` (requires `FORGEJO_METRICS_TOKEN`)
