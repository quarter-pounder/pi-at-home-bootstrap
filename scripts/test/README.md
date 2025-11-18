# Test Scripts

Diagnostic and testing scripts for monitoring and debugging.

## Scripts

- `check-all-containers.sh` - Check all container metrics from Prometheus, including Docker and containerd containers
- `check-cadvisor-labels.sh` - Check what labels are available in cadvisor metrics
- `check-container-names.sh` - Check container names and labels in Prometheus metrics
- `test-cadvisor.sh` - Test cadvisor container status, logs, and metrics endpoint
- `test-runner-queries.sh` - Test Prometheus queries for CI/CD runner status

## Usage

All scripts accept an optional Prometheus URL as the first argument (defaults to `http://192.168.0.58:9090`):

```bash
./scripts/test/test-cadvisor.sh http://192.168.0.58:9090
```

