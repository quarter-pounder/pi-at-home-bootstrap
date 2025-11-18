# GitHub Actions Runner

Self-hosted GitHub Actions runner for executing workflows on the Raspberry Pi.

## Configuration

### Repository Runner

To register the runner with a specific repository:

1. Go to your repository on GitHub
2. Navigate to **Settings** > **Actions** > **Runners** > **New self-hosted runner**
3. Select **Linux** > **ARM64**
4. Copy the registration token
5. Set in `.env`:
   ```
   GITHUB_ACTIONS_RUNNER_REPO_URL=https://github.com/your-username/your-repo
   # Or use short format: your-username/your-repo
   GITHUB_ACTIONS_RUNNER_TOKEN=your-registration-token
   ```

### Organization Runner

To register the runner with an organization:

1. Go to your organization on GitHub
2. Navigate to **Settings** > **Actions** > **Runners** > **New self-hosted runner**
3. Select **Linux** > **ARM64**
4. Copy the registration token
5. Set in `.env`:
   ```
   # Leave GITHUB_ACTIONS_RUNNER_REPO_URL empty for org-level runner
   GITHUB_ACTIONS_RUNNER_TOKEN=your-registration-token
   ```

## Environment Variables

- `GITHUB_ACTIONS_RUNNER_NAME`: Runner name (default: `pi-forge-runner`)
- `GITHUB_ACTIONS_RUNNER_REPO_URL`: Repository URL in format `https://github.com/owner/repo` or `owner/repo` (for repo-level runner). Leave empty for organization-level runner.
- `GITHUB_ACTIONS_RUNNER_TOKEN`: Registration token from GitHub
- `GITHUB_ACTIONS_RUNNER_LABELS`: Comma-separated labels (default: `self-hosted,Linux,ARM64`)
- `GITHUB_ACTIONS_RUNNER_DOCKER_ENABLED`: Enable Docker support (default: `true`)

## Docker vs Host-Based

### Docker-Based (Default)

The runner runs in a Docker container with Docker-in-Docker support. This provides:
- Isolation from the host system
- Easy cleanup of job artifacts
- Consistent execution environment

Set `GITHUB_ACTIONS_RUNNER_DOCKER_ENABLED=true` in `.env`.

### Host-Based

To run jobs directly on the host (without Docker), set `GITHUB_ACTIONS_RUNNER_DOCKER_ENABLED=false`.

**Note:** Host-based execution requires more setup and is less isolated. Consider using Docker-based execution for better security and isolation.

## Usage in Workflows

Use the runner in your workflows by specifying the labels:

```yaml
jobs:
  build:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: echo "Building on Pi!"
```

Or use specific labels:

```yaml
jobs:
  build:
    runs-on: [self-hosted, Linux, ARM64]
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: echo "Building on Pi!"
```

## Security Considerations

- Self-hosted runners execute code from your workflows
- Only use with trusted repositories
- Consider using organization-level runners for better access control
- Monitor runner logs for suspicious activity
- Regularly update the runner image for security patches

## Troubleshooting

### Runner Not Appearing in GitHub

1. Check the runner logs: `docker logs github-actions-runner`
2. Verify the registration token is correct
3. Ensure the runner has internet connectivity
4. Check that the token hasn't expired (tokens expire after 1 hour if not used)

### Jobs Not Starting

1. Check the runner status in GitHub UI
2. Verify the workflow's `runs-on` label matches the runner's labels
3. Check runner logs for errors
4. Ensure Docker is running if `DOCKER_ENABLED=true`

### Docker Issues

1. Verify Docker socket is accessible: `ls -l /var/run/docker.sock`
2. Check Docker daemon is running: `docker ps`
3. Ensure the runner has permissions to access Docker socket


