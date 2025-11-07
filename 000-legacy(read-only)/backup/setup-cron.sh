#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SCRIPT_DIR="$(pwd)/backup"

echo "[i] Setting up automatic backup schedule..."

(crontab -l 2>/dev/null | grep -v "gitlab-backup"; cat <<EOF
0 2 * * * ${SCRIPT_DIR}/backup.sh >> /var/log/gitlab-backup.log 2>&1
EOF
) | crontab -

echo "[i] Backup cron job installed (runs daily at 2 AM)"
echo "[i] Current crontab:"
crontab -l

echo "[i] Creating log file..."
sudo touch /var/log/gitlab-backup.log
sudo chown ${USER}:${USER} /var/log/gitlab-backup.log

echo "[i] Backup schedule configured!"

