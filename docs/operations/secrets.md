# Encrypted Secrets Workflow

## Files
- `config-registry/env/secrets.env.vault` – Encrypted environment variables rendered into templates.
- `.vault_pass` – Local vault password file (ignored by Git); stored at repository root.

## Bootstrap Preparation
1. Generate a strong password and place it in `.vault_pass`:
   ```bash
   openssl rand -base64 48 > .vault_pass
   chmod 600 .vault_pass
   ```
2. Ensure the host has `ansible-vault` available (installed via `bootstrap/02-install-core.sh`).

## Managing Secrets
- `make vault-create` – Creates `secrets.env.vault`. Uses `.vault_pass` when present; otherwise prompts for a password.
- `make vault-edit` – Opens the vault for editing with `ansible-vault edit`.
- `make vault-view` – Displays decrypted contents without writing to disk.

The renderer automatically decrypts `secrets.env.vault` when both files exist. Missing prerequisites trigger warnings but do not abort template generation.

## Recommended Keys
Store the following sensitive values inside the vault (non-exhaustive):
- `GITLAB_ROOT_PASSWORD`
- `GITLAB_RUNNER_TOKEN`
- `REGISTRY_HTTP_SECRET`
- `SMTP_PASSWORD`
- `CLOUDFLARE_TUNNEL_TOKEN`
- Any keys prefixed with `*_TOKEN`, `*_PASSWORD`, or cloud credentials

## Operational Notes
- Keep `.vault_pass` distribution-limited; share through a secure secrets manager when multiple operators require access.
- Rotate the vault password whenever access changes. After rotation, update `.vault_pass` copies and re-encrypt the vault with `ansible-vault rekey`.
- Never commit decrypted secrets or the password file. Git ignores `.vault_pass` by default.

