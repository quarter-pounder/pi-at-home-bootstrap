# Registry Domain

Standalone Docker Distribution instance backed by GitLab for token auth. Runs beside the GitLab domain but keeps its lifecycle distinct.

## Contract
- **Inputs**
  - Rendered Compose file (`domains/registry/templates/compose.yml.tmpl`)
  - Rendered registry config (`domains/registry/templates/config.yml.tmpl`)
  - Shared environment values (`REGISTRY_*`, `PORT_REGISTRY_*`, `GITLAB_EXTERNAL_URL`)
- **Outputs**
  - Container registry endpoint on `PORT_REGISTRY_HTTP`
- **State**: `/srv/registry`
- **Lifecycle**: `docker compose up/down` via `make deploy DOMAIN=registry`
- **Relationships** (mirrors `domains.yml`)
  - `placement: tunnel`
  - `requires: [gitlab]`
  - `exposes_to: [tunnel, gitlab]`
  - `consumes: [gitlab]`

## Configuration Flow
1. Ensure GitLab domain is rendered first so the shared network (`gitlab-shared`) exists.
2. Generate metadata (`make generate-metadata`) and commit drift.
3. Render registry templates (`make render DOMAIN=registry ENV=<env>`).
4. Deploy with `make deploy DOMAIN=registry`.

## Templates
- `domains/registry/templates/compose.yml.tmpl`
  - Mounts `/srv/registry` and the rendered `config.yml`
  - Attaches to a private network plus the shared `gitlab-shared` bridge so GitLab can reach `gitlab-registry:5000`
- `domains/registry/templates/config.yml.tmpl`
  - Configures HTTP token auth against GitLab (`REGISTRY_TOKEN_REALM`)
  - Requires `REGISTRY_HTTP_SECRET` to be populated (ideally stored in `secrets.env.vault`)

## Operational Notes
- Set `REGISTRY_HTTP_SECRET` to a long random string before render; pushes/pulls will fail if it is blank.
- The registry expects GitLab to be reachable as `http://gitlab` on the shared Docker network; ensure GitLab is deployed and attached to `gitlab-shared`.
- Prometheus/Grafana scrape coverage is handled by the monitoring domain; no exporters run inside the registry container today.
- Additional secret-handling guidance: `docs/operations/secrets.md`

