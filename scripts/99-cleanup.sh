#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

RED=$(tput setaf 1); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

echo "${RED}[!] WARNING: This will remove all GitLab data and services!${RESET}"
echo ""
echo "This will:"
echo "  - Stop and remove all Docker containers"
echo "  - Remove all Docker volumes"
echo "  - Delete all GitLab data in /srv"
echo "  - Remove Cloudflare tunnel"
echo "  - Remove fail2ban GitLab rules"
echo "  - Keep Docker, firewall, and security settings"
echo ""
read -p "Type 'delete everything' to confirm: " -r
if [[ "$REPLY" != "delete everything" ]]; then
  echo "Cleanup cancelled"
  exit 0
fi

echo ""
echo "[i] Stopping services..."
cd compose
docker compose -f gitlab.yml down -v 2>/dev/null || true
docker compose -f monitoring.yml down -v 2>/dev/null || true
docker compose -f adblocker.yml down -v 2>/dev/null || true
cd ..

echo "[i] Removing data directories..."
sudo rm -rf /srv/gitlab
sudo rm -rf /srv/gitlab-runner
sudo rm -rf /srv/registry
sudo rm -rf /srv/prometheus
sudo rm -rf /srv/grafana
sudo rm -rf /srv/loki
sudo rm -rf /srv/alertmanager
sudo rm -rf /srv/pihole
sudo rm -rf /srv/unbound
sudo rm -rf /srv/gitlab-mirror
sudo rm -rf /srv/gitlab-dr

echo "[i] Removing backups..."
if [[ -d "${BACKUP_DIR:-/srv/backups}/gitlab" ]]; then
  read -p "Remove backups too? (yes/no): " -r
  if [[ $REPLY =~ ^yes$ ]]; then
    sudo rm -rf "${BACKUP_DIR:-/srv/backups}/gitlab"
  fi
fi

echo "[i] Removing Cloudflare tunnel..."
sudo systemctl stop cloudflared 2>/dev/null || true
sudo systemctl disable cloudflared 2>/dev/null || true
sudo rm -f /etc/systemd/system/cloudflared.service
sudo rm -rf /etc/cloudflared

echo "[i] Removing fail2ban GitLab rules..."
sudo rm -f /etc/fail2ban/filter.d/gitlab.conf
sudo rm -f /etc/fail2ban/jail.d/gitlab.conf
sudo systemctl restart fail2ban 2>/dev/null || true

echo "[i] Removing systemd services..."
sudo systemctl stop prometheus-webhook-receiver 2>/dev/null || true
sudo systemctl disable prometheus-webhook-receiver 2>/dev/null || true
sudo systemctl stop gitlab-dr-status 2>/dev/null || true
sudo systemctl disable gitlab-dr-status 2>/dev/null || true
sudo systemctl stop gitlab-mirror-webhook 2>/dev/null || true
sudo systemctl disable gitlab-mirror-webhook 2>/dev/null || true
sudo rm -f /etc/systemd/system/prometheus-webhook-receiver.service
sudo rm -f /etc/systemd/system/gitlab-dr-status.service
sudo rm -f /etc/systemd/system/gitlab-mirror-webhook.service

echo "[i] Removing cron jobs..."
crontab -l 2>/dev/null | grep -v gitlab-backup | crontab - 2>/dev/null || true

echo ""
echo "${YELLOW}Cleanup complete.${RESET}"
echo ""
echo "To fully reset, you may also want to:"
echo "  - Remove Docker: sudo apt purge docker-ce docker-ce-cli containerd.io"
echo "  - Remove this repo: cd .. && rm -rf gitlab-bootstrap"

