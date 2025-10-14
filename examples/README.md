# GitLab CI/CD Examples

Example `.gitlab-ci.yml` files for common project types.

## Usage

Copy the appropriate example to your project's root as `.gitlab-ci.yml`:

```bash
cp examples/gitlab-ci-nodejs.yml /path/to/your/project/.gitlab-ci.yml
```

Edit as needed for your project.

## Examples

### Docker Build & Push
`gitlab-ci-docker.yml` - Build Docker images and push to GitLab registry

Key features:
- Multi-stage: build, test, deploy
- Pushes to GitLab container registry
- Tags with commit SHA and latest
- Manual deployment trigger

### Node.js Project
`gitlab-ci-nodejs.yml` - Node.js/npm projects

Key features:
- Caching node_modules
- Linting and testing
- Code coverage reports
- Build artifacts

### Python Project
`gitlab-ci-python.yml` - Python projects

Key features:
- Virtual environment setup
- pytest with coverage
- pylint code quality
- Docker image build

## Variables

Most examples use these built-in GitLab CI/CD variables:

- `$CI_REGISTRY` - GitLab container registry URL
- `$CI_REGISTRY_IMAGE` - Your project's registry path
- `$CI_REGISTRY_USER` - Registry username (automatic)
- `$CI_REGISTRY_PASSWORD` - Registry password (automatic)
- `$CI_COMMIT_SHA` - Current commit hash
- `$CI_PROJECT_DIR` - Project directory path

## Customization

Adjust these for your needs:
- Node/Python versions in `image:`
- Test commands in `script:`
- Deployment targets
- When rules (`only:`, `when:`)
- Cache paths

## Registry Authentication

The runner is pre-configured to access your GitLab registry. No additional setup needed.

## Tips

- Use `cache:` for dependencies to speed up builds
- Use `artifacts:` to pass data between stages
- Set `when: manual` for production deployments
- Use `only:` to limit when jobs run
- Add coverage reporting to track code quality

