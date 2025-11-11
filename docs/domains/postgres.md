# PostgreSQL Domain

Provides the shared PostgreSQL instance used by Forgejo and Woodpecker.

## Contract
- **Inputs**
  - Rendered Compose file (`domains/postgres/templates/compose.yml.tmpl`)
  - Initialization script (`domains/postgres/templates/init.sql.tmpl`)
  - Environment secrets (`POSTGRES_*` values stored in the vault)
- **Outputs**
  - Postgres service on `PORT_POSTGRES_POSTGRES`
- **State**: `/srv/postgres/data`
- **Lifecycle**: `make deploy DOMAIN=postgres`
- **Relationships**
  - `placement: local`
  - `requires: []`
  - `exposes_to: [forgejo, woodpecker]`
  - `consumes: []`

## Notes
- `init.sql` creates dedicated users/databases for Forgejo and Woodpecker on first launch.
- Backups should dump both `forgejo` and `woodpecker` databases.
- Update secrets (`POSTGRES_SUPERUSER_PASSWORD`, per-database passwords) via the vault before deploy.

