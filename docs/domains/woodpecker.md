# Woodpecker Domain

Woodpecker provides lightweight CI/CD for Forgejo repositories.
The server authenticates users via Forgejo OAuth and stores all state in PostgreSQL.
It is intentionally minimal: fast startup, no runners baked in, and clean network boundaries.

---

## Contract

### Inputs
- Rendered Compose file
  `domains/woodpecker/templates/compose.yml.tmpl`
- Environment values (`WOODPECKER_*`)
  Includes OAuth keys, database credentials, and signing secrets
- Forgejo OAuth configuration
  (client ID / secret stored in the vault)

### Outputs
- Web UI and API → `PORT_WOODPECKER_HTTP`
- Prometheus metrics → `PORT_WOODPECKER_METRICS`
  Defaults to **9001** to avoid colliding with the gRPC runner port

### State
`/srv/woodpecker/server`

### Lifecycle
`make deploy DOMAIN=woodpecker`
`make destroy DOMAIN=woodpecker`

### Relationships
(from `domains.yml`)
- `placement: tunnel`
- `requires: [forgejo, postgres]`
- `exposes_to: [tunnel, monitoring]`
- `consumes: [forgejo, postgres]`

### Operational Checklist
See:
`docs/operations/forgejo-woodpecker-setup.md`
This covers:
- OAuth configuration in Forgejo
- Generating and injecting signing secrets
- Pairing the server with runners
- Validating callback URLs and user scopes

---

## Port Model

Woodpecker exposes **three separate listeners** inside the container:

| Purpose | Internal Port | Notes |
|--------|---------------|-------|
| HTTP Web UI / API | `8000` | Exposed as `PORT_WOODPECKER_HTTP` |
| gRPC Runner API | `9000` | Runners *must* use `woodpecker:9000` (internal) |
| Metrics endpoint | `${PORT_WOODPECKER_METRICS}` | Defaults to `9001` |

Keep these values stable in the templates. Too many examples online where people accidentally map the gRPC port externally, causing the runner handshake to fail.

---

# Woodpecker Runner Domain

A separate domain provides the execution runner.
It pulls jobs from the server’s gRPC endpoint and executes builds with minimal overhead.

## Contract

### Inputs
- Rendered Compose file
  `domains/woodpecker-runner/templates/compose.yml.tmpl`
- `WOODPECKER_SERVER`
- `WOODPECKER_AGENT_SECRET` or registration token
- Optional: resource limits via metadata

### Outputs
- Runner process reporting to the Woodpecker server
- Prometheus metrics via cAdvisor (not exposed by the runner itself)

### State
`/srv/woodpecker/runner`
(usually only contains logs; builds run in ephemeral containers)

### Lifecycle
`make deploy DOMAIN=woodpecker-runner`
`make destroy DOMAIN=woodpecker-runner`

### Relationships
- `placement: local`
- `requires: [woodpecker]`
- `exposes_to: [monitoring]`
- `consumes: [woodpecker]`

## Notes

- The runner must connect to the **internal** URL:
  `WOODPECKER_SERVER=http://woodpecker:9000`
- Job execution runs in sibling containers, not in the runner container itself
- CPU spikes during builds are expected; dashboards should watch container-level metrics
- Runner secrets must be updated via the vault to avoid drift

