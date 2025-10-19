#!/bin/bash

# Fix GitLab container permissions
# This script addresses common permission issues with GitLab on ARM64

set -euo pipefail

echo "[i] Fixing GitLab container permissions..."

# Check if GitLab container is running
if ! docker ps | grep -q "gitlab"; then
    echo "[!] GitLab container is not running"
    exit 1
fi

echo "[i] Running update-permissions inside GitLab container..."
docker exec gitlab update-permissions

echo "[i] Fixing specific permission issues..."

# Fix log file permissions
docker exec gitlab bash -c "
    mkdir -p /var/log/gitlab/gitlab-rails
    mkdir -p /var/log/gitlab/puma
    mkdir -p /var/log/gitlab/sidekiq
    mkdir -p /var/log/gitlab/gitaly
    mkdir -p /var/log/gitlab/gitlab-shell
    mkdir -p /var/log/gitlab/gitlab-workhorse

    chown -R git:git /var/log/gitlab/
    chmod -R 755 /var/log/gitlab/
"

# Fix data directory permissions
docker exec gitlab bash -c "
    mkdir -p /var/opt/gitlab/git-data
    mkdir -p /var/opt/gitlab/gitlab-rails
    mkdir -p /var/opt/gitlab/gitlab-shell
    mkdir -p /var/opt/gitlab/gitaly

    chown -R git:git /var/opt/gitlab/git-data/
    chown -R git:git /var/opt/gitlab/gitlab-rails/
    chown -R git:git /var/opt/gitlab/gitlab-shell/
    chown -R git:git /var/opt/gitlab/gitaly/

    chmod -R 755 /var/opt/gitlab/
"

echo "[i] Restarting GitLab container..."
docker restart gitlab

echo "[OK] GitLab permissions fixed and container restarted"
echo "[i] Monitor logs with: docker logs gitlab -f"
