#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env || true

RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)
trap 'echo ""; echo "${YELLOW}[!] Setup interrupted by user.${RESET}"; exit 1' INT TERM

cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║     GitLab Services Setup (Part 2)                         ║
╚════════════════════════════════════════════════════════════╝
EOF

if ! command -v docker >/dev/null 2>&1 || ! docker ps >/dev/null 2>&1; then
  echo "${RED}[!] Docker is not accessible.${RESET} Log out/in after install, then retry."
  exit 1
fi

step() {
  echo ""
  echo "──────────────────────────────────────────────"
  echo "${YELLOW}Step $1:${RESET} $2"
  echo "──────────────────────────────────────────────"
}

step 4 "Setting up GitLab..."
./scripts/04-setup-gitlab.sh

echo ""
echo "${YELLOW}[!] Before continuing, please:${RESET}"
echo "    1. Login to GitLab at http://$(hostname -I | awk '{print $1}')"
echo "    2. Go to Admin Area → CI/CD → Runners"
echo "    3. Create a new instance runner and copy the token"
echo "    4. Add it to .env as GITLAB_RUNNER_TOKEN"
echo ""
read -p "Have you updated .env? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
  echo "Please update .env and rerun this script."
  exit 0
fi

step 5 "Registering GitLab Runner..."
./scripts/05-register-runner.sh

step 6 "Setting up monitoring..."
./scripts/06-setup-monitoring.sh

step 7 "Setting up backups..."
./backup/setup-cron.sh

step 8 "Setting up ad blocker (optional)..."
if [[ -n "${PIHOLE_WEB_PASSWORD:-}" ]]; then
  ./scripts/20-setup-adblocker.sh
else
  echo "Skipping Pi-hole setup (PIHOLE_WEB_PASSWORD not set)"
fi

step 9 "Setting up disaster recovery (optional)..."
if [[ -n "${GITLAB_CLOUD_TOKEN:-}" && -n "${DR_WEBHOOK_URL:-}" ]]; then
  ./scripts/19-setup-complete-dr.sh
else
  echo "Skipping DR setup (GITLAB_CLOUD_TOKEN or DR_WEBHOOK_URL not set)"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete!                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Setup Cloudflare Tunnel: ${YELLOW}./scripts/07-setup-cloudflare-tunnel.sh${RESET}"
echo "  2. Run health check:        ${YELLOW}./scripts/08-health-check.sh${RESET}"
echo "  3. Test backup:             ${YELLOW}./backup/backup.sh${RESET}"
echo ""
echo "Access your services:"
IP=$(hostname -I | awk '{print $1}')
echo "  GitLab:       http://$IP"
echo "  Grafana:      http://$IP:3000"
echo "  Prometheus:   http://$IP:9090"
echo "  Alertmanager: http://$IP:9093"
if [[ -n "${PIHOLE_WEB_PASSWORD:-}" ]]; then
  echo "  Pi-hole:      http://$IP:8080/admin"
fi
if [[ -n "${GITLAB_CLOUD_TOKEN:-}" && -n "${DR_WEBHOOK_URL:-}" ]]; then
  echo "  DR Status:    http://$IP:8081/status"
fi
echo ""

echo "${GREEN}✓ Setup completed successfully.${RESET}"
