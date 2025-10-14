#!/usr/bin/env bash
set -euo pipefail

cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║     GitLab Services Setup (Part 2)                         ║
╚════════════════════════════════════════════════════════════╝
EOF

if ! docker ps >/dev/null 2>&1; then
  echo "[!] Docker is not accessible. Did you logout and login after installing Docker?"
  exit 1
fi

echo ""
echo "Step 4/7: Setting up GitLab..."
./scripts/04-setup-gitlab.sh

echo ""
echo "[!] Before continuing, you need to:"
echo "    1. Login to GitLab at http://$(hostname -I | awk '{print $1}')"
echo "    2. Go to Admin Area > CI/CD > Runners"
echo "    3. Create new instance runner and copy the token"
echo "    4. Add token to .env as GITLAB_RUNNER_TOKEN"
echo ""
read -p "Have you added GITLAB_RUNNER_TOKEN to .env? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
  echo "Please complete GitLab runner setup and run this script again."
  exit 0
fi

echo ""
echo "Step 5/7: Registering GitLab Runner..."
./scripts/05-register-runner.sh

echo ""
echo "Step 6/7: Setting up monitoring..."
./scripts/06-setup-monitoring.sh

echo ""
echo "Step 7/7: Setting up backups..."
./backup/setup-cron.sh

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete!                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Setup Cloudflare Tunnel: ./scripts/07-setup-cloudflare-tunnel.sh"
echo "  2. Run health check: ./scripts/08-health-check.sh"
echo "  3. Test backup: ./backup/backup.sh"
echo ""
echo "Access your services:"
echo "  GitLab:     http://$(hostname -I | awk '{print $1}')"
echo "  Grafana:    http://$(hostname -I | awk '{print $1}'):3000"
echo "  Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo ""

