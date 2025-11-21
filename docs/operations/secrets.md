# Encrypted Secrets Workflow

The secrets layer provides encrypted environment variables for every domain. All rendered templates receive decrypted values automatically during `make render`, with clear warnings if prerequisites are missing.

## Files
- `config-registry/env/secrets.env.vault`: Encrypted environment variables rendered into templates.
- `.vault_pass`: Local vault password file (ignored by Git); stored at repository root.

## Bootstrap Preparation
1. Generate a strong password and place it in `.vault_pass`:
   ```bash
   openssl rand -base64 48 > .vault_pass
   chmod 600 .vault_pass
   ```
2. Ensure the host has `ansible-vault` available (installed via `bootstrap/02-install-core.sh`).

## Managing Secrets
- `make vault-create`: Creates `secrets.env.vault`. Uses `.vault_pass` when present; otherwise prompts for a password.
- `make vault-edit`: Opens the vault for editing with `ansible-vault edit`.
- `make vault-view`: Displays decrypted contents without writing to disk.

### Editing Workflow
1. Ensure `.vault_pass` exists (or be ready to enter the password when prompted).
2. Run:
   ```bash
   make vault-edit
   ```
   This opens ansible-vault edit using $EDITOR (defaults to vi, don't even think about nano).

3. Add or update key/value pairs in `KEY=value` form, e.g.:
   ```
   FORGEJO_ADMIN_PASSWORD=change-me
   FORGEJO_APP_SECRET=$(openssl rand -hex 32)
   POSTGRES_SUPERUSER_PASSWORD=very-secret
   POSTGRES_PASSWORD_FORGEJO=super-secret
   POSTGRES_PASSWORD_WOODPECKER=extrodinary-secret
   SMTP_PASSWORD=super-secret
   REGISTRY_HTTP_SECRET=long-random-string
   WOODPECKER_FORGEJO_CLIENT_SECRET=oauth-secret
   WOODPECKER_AGENT_SECRET=$(openssl rand -hex 32)
   ```
4. Save and exit; `ansible-vault` re-encrypts the file automatically.

> Tip: set `EDITOR="nano"` or another favorite editor before running `make vault-edit` if you really love nano.

**Automatic Secret Loading**

During template rendering, secrets are decrypted when:
   - the vault exists,
	- .vault_pass exists,
	- and ansible-vault is installed

If any component is missing, the renderer logs warnings but does not abort.

### Required secrets
```
FORGEJO_APP_SECRET=change-me
FORGEJO_METRICS_TOKEN=change-me
FORGEJO_ADMIN_USERNAME=forgejo-admin
FORGEJO_ADMIN_PASSWORD=change-me
FORGEJO_ADMIN_EMAIL=admin@example.com
SMTP_ADDRESS=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=forgejo@example.com
SMTP_PASSWORD=change-me
SMTP_FROM=Forgejo <forgejo@example.com>
```

## Recommended Keys

Store the following sensitive values inside the vault (non-exhaustive):
- `FORGEJO_ADMIN_PASSWORD`
- `FORGEJO_APP_SECRET`
- `FORGEJO_LFS_JWT_SECRET`
- `FORGEJO_METRICS_TOKEN`
- `POSTGRES_SUPERUSER_PASSWORD`
- `POSTGRES_PASSWORD_FORGEJO`
- `POSTGRES_PASSWORD_WOODPECKER`
- `WOODPECKER_FORGEJO_CLIENT_SECRET`
- `WOODPECKER_AGENT_SECRET`
- `REGISTRY_HTTP_SECRET`
- `SMTP_PASSWORD`
- `CLOUDFLARE_TUNNEL_TOKEN`
- Any keys prefixed with `*_TOKEN`, `*_PASSWORD`, or cloud credentials

## Operational Notes
- Keep `.vault_pass` distribution-limited; share through a secure secrets manager when multiple operators require access.
- Rotate the vault password whenever access changes. After rotation, update `.vault_pass` copies and re-encrypt the vault with `ansible-vault rekey`.
- Never commit decrypted secrets or the password file. Git ignores `.vault_pass` by default.

