# GitLab Domain

## Inputs
- `compose.yml.tmpl` renders the Omnibus container definition.
- `gitlab.rb.tmpl` renders `/etc/gitlab/gitlab.rb`.
- Environment variables in `config-registry/env/*.env` provide `GITLAB_*` and SMTP settings.

## Outputs
- HTTPS: `${PORT_GITLAB_HTTPS}`
- HTTP: `${PORT_GITLAB_HTTP}`
- SSH: `${PORT_GITLAB_SSH}`
- Metrics: `${PORT_GITLAB_METRICS}` (workhorse exporter)

## State
- `/srv/gitlab/config`
- `/srv/gitlab/data`
- `/srv/gitlab/logs`
- `/srv/gitlab/ssl`

## Lifecycle
1. `make generate-metadata`
2. `make validate`
3. `make render DOMAIN=gitlab ENV=<env>`
4. `make deploy DOMAIN=gitlab`

