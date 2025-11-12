# Forgejo + Woodpecker Setup Runbook

This checklist assumes bootstrap is complete (`make deploy` succeeded for `postgres`, `forgejo`, `woodpecker`, and `woodpecker-runner`). Secrets live in `config-registry/env/secrets.env.vault`; use `make vault-edit` to modify them.

## 1. Populate Vault Secrets

| Key | Description |
| --- | --- |
| `FORGEJO_ADMIN_PASSWORD` | Initial admin account password rendered into the container. |
| `FORGEJO_APP_SECRET` | Forgejo session signing secret. |
| `FORGEJO_LFS_JWT_SECRET` | Secret for LFS operations. |
| `FORGEJO_METRICS_TOKEN` | Bearer token Prometheus uses to scrape Forgejo metrics. |
| `SMTP_PASSWORD` / `SMTP_USERNAME` | Gmail (or other provider) credentials. Use an App Password when 2FA is enabled. |
| `POSTGRES_SUPERUSER_PASSWORD` | Password for `postgres` user. |
| `POSTGRES_PASSWORD_FORGEJO` | Database password Forgejo uses. |
| `POSTGRES_PASSWORD_WOODPECKER` | Database password Woodpecker uses. |
| `WOODPECKER_AGENT_SECRET` | Shared secret between Woodpecker server and runner. |
| `WOODPECKER_FORGEJO_CLIENT_ID` | OAuth client ID issued by Forgejo (see below). |
| `WOODPECKER_FORGEJO_CLIENT_SECRET` | OAuth client secret. |
| `REGISTRY_HTTP_SECRET` | Token secret for the container registry. |
| `CLOUDFLARE_TUNNEL_TOKEN` / `CLOUDFLARE_API_TOKEN` | Only if Cloudflare Tunnel is managed from this host. |

After editing the vault:

```bash
make render DOMAIN=forgejo
make deploy DOMAIN=forgejo
make render DOMAIN=woodpecker
make deploy DOMAIN=woodpecker
```

## 2. Forgejo Bootstrap Checklist

1. **Confirm admin account**
   - Log in at `https://forgejo.<DOMAIN>` with `FORGEJO_ADMIN_USERNAME` / `FORGEJO_ADMIN_PASSWORD`.
   - Change the password in the UI if desired; update the vault to match.
2. **SSH host keys**
   - Forgejo stores keys under `/srv/forgejo/data/ssh`. If migrating from another instance, copy the existing `id_rsa`/`id_ed25519` pairs before redeploying.
3. **SMTP test**
   - Navigate to **Site Administration → Configuration → Mailer**.
   - Click *Test configuration*; expect a success toast. The Gmail App Password is required when 2FA is enabled.
4. **Repository mirror (optional)**
   - Create a personal access token on GitHub with `repo` scope.
   - In Forgejo, create a new repository mirror pointing at the GitHub URL using that token.
   - Store the token in the vault (`FORGEJO_GITHUB_MIRROR_TOKEN`, if you wish to reuse it later).
5. **Metrics**
   - `Settings → Applications → Manage Access Tokens` → create a PAT named `prometheus` with `scope=read:metrics` if you prefer PAT-based scraping. Otherwise rely on `FORGEJO_METRICS_TOKEN` in the environment.

## 3. Woodpecker OAuth Integration

1. **Create OAuth application in Forgejo**
   - Go to **Settings → Applications → Manage OAuth2 Applications**.
   - Name: `Woodpecker`
   - Redirect URI: `${WOODPECKER_HOST}/authorize` (defaults to `https://ci.<DOMAIN>/authorize`).
   - Submit and copy the `Client ID` and `Client Secret`.
2. **Store credentials in the vault**
   - `WOODPECKER_FORGEJO_CLIENT_ID`
   - `WOODPECKER_FORGEJO_CLIENT_SECRET`
   - `WOODPECKER_AGENT_SECRET` (generate with `openssl rand -hex 32` if missing).
3. **Redeploy Woodpecker services**

   ```bash
   make render DOMAIN=woodpecker
   make deploy DOMAIN=woodpecker

   make render DOMAIN=woodpecker-runner
   make deploy DOMAIN=woodpecker-runner
   ```

4. **Initial login**
   - Visit `https://ci.<DOMAIN>` and click *Sign in with Forgejo*.
   - Approve the OAuth consent screen. The first authenticated user listed in `WOODPECKER_ADMIN_USERS` becomes admin.
5. **Runner verification**
   - `docker logs woodpecker-runner` should show `agent connected` messages.
   - In the Woodpecker UI, the runner appears under **Agents** with status `running`.

## 4. Post-Checks

- Prometheus target `woodpecker:9000` is `UP` (requires successful OAuth secret deployment).
- Grafana dashboards show Forgejo/Woodpecker availability and request metrics.
- Alertmanager receives email notifications (check Gmail mailer logs in Forgejo).

Keep this file synced when configuration flows change. Suggestions and improvements welcome.
