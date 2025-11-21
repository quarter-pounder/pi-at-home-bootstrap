# PostgreSQL Domain

This domain provides the shared PostgreSQL instance consumed by Forgejo and Woodpecker.
It is intentionally simple: one container, one volume, two service users, no surprises.

---

## Contract

### Inputs
- Rendered Compose file
  `domains/postgres/templates/compose.yml.tmpl`
- Initialization script
  `domains/postgres/templates/init.sql.tmpl`
- Secret environment variables (`POSTGRES_*`) sourced from the vault

### Outputs
- PostgreSQL service → `PORT_POSTGRES_POSTGRES`

### State
`/srv/postgres/data`

### Lifecycle
`make deploy DOMAIN=postgres`
`make destroy DOMAIN=postgres` (keeps data unless manually deleted)

### Relationships
(from `domains.yml`)
- `placement: local`
- `requires: []`
- `exposes_to: [forgejo, woodpecker]`
- `consumes: []`

---

## Initialization

On first start, `init.sql` provisions:

- A dedicated database + user for **Forgejo**
- A dedicated database + user for **Woodpecker**

The script is idempotent from Docker’s perspective: it only runs when
`/srv/postgres/data` is empty.

---

## Secrets

Passwords are sourced from the encrypted vault:

- `POSTGRES_SUPERUSER_PASSWORD`
- `POSTGRES_FORGEJO_PASSWORD`
- `POSTGRES_WOODPECKER_PASSWORD`

Update secrets with:

```
make vault-edit
```

Re-render and redeploy:

```
make render DOMAIN=postgres
make deploy DOMAIN=postgres
```

---

## Backup Notes

Backups should include **both** application databases:

- `forgejo`
- `woodpecker`

Plus the PostgreSQL global metadata for consistency.

The recommended tooling for domain-aware backups is documented in
`docs/operations/backups.md`.

---

## Operational Notes

- The domain exposes only one service port: `PORT_POSTGRES_POSTGRES`
- The container runs with a fixed, declared volume (`/srv/postgres/data`)
- Other domains must link to Postgres only over the internal network
- No PgBouncer or replication is deployed — the stack is intentionally minimal
