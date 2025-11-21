# Registry Domain

Standalone Docker Distribution instance backed by Forgejo for token auth. Runs beside the Forgejo domain but keeps its lifecycle distinct.

## Contract
- **Inputs**
  - Rendered Compose file (`domains/registry/templates/compose.yml.tmpl`)
  - Rendered registry config (`domains/registry/templates/config.yml.tmpl`)
  - Shared environment values (`REGISTRY_*`, `PORT_REGISTRY_*`, `FORGEJO_EXTERNAL_URL`)
- **Outputs**
  - Container registry endpoint on `PORT_REGISTRY_HTTP`
- **State**: `/srv/registry`
- **Lifecycle**: `docker compose up/down` via `make deploy DOMAIN=registry`
- **Relationships** (mirrors `domains.yml`)
  - `placement: tunnel`
  - `requires: [forgejo]`
  - `exposes_to: [tunnel, forgejo]`
  - `consumes: [forgejo]`

## Configuration Flow
1. Ensure Forgejo domain is rendered first so the shared network (`forgejo-network`) exists.
2. Generate metadata (`make generate-metadata`) and commit drift.
3. Render registry templates (`make render DOMAIN=registry ENV=<env>`).
4. Deploy with `make deploy DOMAIN=registry`.

## Templates
- `domains/registry/templates/compose.yml.tmpl`
  - Mounts `/srv/registry` and the rendered `config.yml`
  - Attaches to an internal network plus the shared `forgejo-network` bridge so Forgejo can reach `forgejo-registry:5000`
- `domains/registry/templates/config.yml.tmpl`
  - Configures HTTP token auth against Forgejo (`REGISTRY_TOKEN_REALM`)
  - Requires `REGISTRY_HTTP_SECRET` to be populated (ideally stored in `secrets.env.vault`)

## Operational Notes
- **Secret requirement:** Set `REGISTRY_HTTP_SECRET` to a long random string (e.g., `openssl rand -hex 32`). Without it, pushes/pulls will fail with 401 errors.
- **Forgejo dependency:** The registry resolves Forgejo internally as `http://forgejo` via the shared Docker network. Forgejo must be deployed and reachable before registry authentication can succeed.
- **Monitoring:** The registry has no built-in exporters. Monitoring coverage (availability, container metrics, logs) comes from the monitoring domain.
- For secret-handling conventions and vault usage: see `docs/operations/secrets.md`.

