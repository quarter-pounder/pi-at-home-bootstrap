# GitHub Actions Runner Management

## Overview

The stack supports multiple GitHub Actions runner instances, each identified by a unique name. Each runner is managed independently with its own configuration, container, and data directory.

## Make Targets

```bash
# Add a new runner instance
make add-github-runner NAME=<name> \
  REPO_URL=<url> \
  TOKEN=<token> \
  LABELS=<labels> \
  DOCKER_ENABLED=<true|false>

# Bring down a specific runner (creates alert suppression marker)
make github-runner-down NAME=<name>

# Destroy a runner (removes container, data, and configuration)
make destroy-github-runner NAME=<name>

# List all configured runners
make list-github-runners

# Render compose file for a runner
make render-github-runner NAME=<name>

# Deploy a runner
make deploy-github-runner NAME=<name>
```

## Implementation Details

### Runner Configuration

Each runner has its own environment file:
```
config-registry/env/github-actions-runner-<name>.env
```

Containing:
- `GITHUB_ACTIONS_RUNNER_NAME=<name>`
- `GITHUB_ACTIONS_RUNNER_REPO_URL=<url>` (required)
- `GITHUB_ACTIONS_RUNNER_TOKEN=<token>` (required)
- `GITHUB_ACTIONS_RUNNER_LABELS=<labels>` (default: `self-hosted,Linux,ARM64`)
- `GITHUB_ACTIONS_RUNNER_DOCKER_ENABLED=<true|false>` (default: `true`)

### Storage and Containers

- **Data directory**: `/srv/github-actions-runner-<name>/`
- **Container name**: `github-actions-runner-<name>`
- **Generated compose**: `generated/github-actions-runner-<name>/compose.yml`

### Monitoring Integration

- Dashboard queries use regex patterns (`name=~"github-actions-runner.*"`) to automatically discover all runners
- Alert suppression works per-runner using container name patterns
- The "Currently Online Runners" count includes all instances
- Runner status panels show individual status (Offline/Idle/Active) for each runner

### Alert Suppression

When a runner is brought down with `make github-runner-down`, an alert suppression marker is created at `/srv/monitoring/alert-suppression/github-actions-runner-<name>.down`. This prevents false alerts for intentionally stopped runners.


