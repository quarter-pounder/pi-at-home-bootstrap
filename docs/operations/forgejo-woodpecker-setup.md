# Forgejo + Woodpecker Setup Runbook

This runbook assumes bootstrap is complete and the following domains are deployed:

- `postgres`
- `forgejo`
- `woodpecker`
- `woodpecker-runner`

Secrets live in `config-registry/env/secrets.env.vault`.
Use `make vault-edit` to update them.

---

## 1. Populate Vault Secrets

Set or update the following keys before rendering and deploying:

| Key | Description |
| --- | --- |
| `FORGEJO_ADMIN_PASSWORD` | Initial admin password. |
| `FORGEJO_APP_SECRET` | Forgejo session signing secret. |
| `FORGEJO_LFS_JWT_SECRET` | Secret for LFS operations. |
| `FORGEJO_METRICS_TOKEN` | Token Prometheus uses for the `/metrics` endpoint. |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | SMTP credentials (Gmail App Password if 2FA enabled). |
| `POSTGRES_SUPERUSER_PASSWORD` | Password for the `postgres` superuser. |
| `POSTGRES_PASSWORD_FORGEJO` | Password for Forgejo’s database user. |
| `POSTGRES_PASSWORD_WOODPECKER` | Password for Woodpecker’s database user. |
| `WOODPECKER_AGENT_SECRET` | Shared secret between server and runner. |
| `WOODPECKER_FORGEJO_CLIENT_ID` | OAuth client ID from Forgejo. |
| `WOODPECKER_FORGEJO_CLIENT_SECRET` | OAuth client secret. |
| `REGISTRY_HTTP_SECRET` | Token secret for the container registry. |
| `CLOUDFLARE_TUNNEL_TOKEN` / `CLOUDFLARE_API_TOKEN` | If Cloudflare Tunnel is managed from this host. |

After editing:

```bash
make render DOMAIN=forgejo && make deploy DOMAIN=forgejo
make render DOMAIN=woodpecker && make deploy DOMAIN=woodpecker
```

---

## 2. Forgejo Bootstrap Checklist

### 2.1 Admin account
- Log in at `https://forgejo.<DOMAIN>` using
  `FORGEJO_ADMIN_USERNAME` + `FORGEJO_ADMIN_PASSWORD`
- If you update the password in the UI, update the vault accordingly.

### 2.2 SSH host keys
- Keys are stored under `/srv/forgejo/data/ssh/`.
- When migrating from an older instance, copy existing host keys before redeploying.

### 2.3 SMTP test
Navigate to:

```
Site Administration → Configuration → Mailer
```

Click **Test configuration**. Using Gmail requires an **App Password** if 2FA is enabled.

### 2.4 Optional: Repository mirroring
- Create a GitHub PAT with `repo` scope.
- In Forgejo, configure a mirror pointing to the GitHub repo.
- Optionally store the PAT in the vault (`FORGEJO_GITHUB_MIRROR_TOKEN`).

### 2.5 Metrics
If using a personal access token instead of the environment secret:
- Go to `Settings → Applications → Manage Access Tokens`
- Generate a token with `read:metrics`
Otherwise rely on `FORGEJO_METRICS_TOKEN` already set in the vault.

---

## 3. Woodpecker OAuth Integration

### 3.1 Create OAuth application in Forgejo
Navigate to:

```
Settings → Applications → Manage OAuth2 Applications
```

Create:

- **Name:** `Woodpecker`
- **Redirect URI:** `${WOODPECKER_HOST}/authorize`
  (Default: `https://ci.<DOMAIN>/authorize`)

Copy the **Client ID** and **Client Secret**.

### 3.2 Store values in vault

```text
WOODPECKER_FORGEJO_CLIENT_ID
WOODPECKER_FORGEJO_CLIENT_SECRET
WOODPECKER_AGENT_SECRET
```

Generate the agent secret if missing:

```bash
openssl rand -hex 32
```

### 3.3 Redeploy services

```bash
make render DOMAIN=woodpecker && make deploy DOMAIN=woodpecker
make render DOMAIN=woodpecker-runner && make deploy DOMAIN=woodpecker-runner
```

### 3.4 First login
- Visit `https://ci.<DOMAIN>`
- Click **Sign in with Forgejo**
- Approve OAuth consent
- The first user in `WOODPECKER_ADMIN_USERS` becomes the Woodpecker admin

### 3.5 Runner health
Check logs:

```bash
docker logs woodpecker-runner
```

Expect to see:

```
agent connected
```

In the Woodpecker UI, the runner appears under **Agents** with status `running`.

---

## 4. Post-Checks

- Prometheus successfully scrapes `woodpecker:9000`
- Grafana panels show Forgejo + Woodpecker availability
- Alertmanager receives emails for alert triggers
- `woodpecker-runner` remains connected after restarting the server container

---

Keep this runbook updated when configuration flows change.
