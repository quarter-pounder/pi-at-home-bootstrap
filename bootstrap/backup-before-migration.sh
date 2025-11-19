#!/usr/bin/env bash
# Quick backup migration
set -euo pipefail

cd "$(dirname "$0")/.."
source bootstrap/utils.sh

BACKUP_DIR="$HOME/pi-forge-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

log_info "Backing up to: $BACKUP_DIR"

# Application data
log_info "Backing up /srv data (this may take a while)..."
if sudo tar -czf "$BACKUP_DIR/srv-data.tar.gz" -C /srv . 2>/dev/null; then
  log_success "Application data backed up"
  du -h "$BACKUP_DIR/srv-data.tar.gz"
else
  log_error "Failed to backup /srv data"
  exit 1
fi

# Configuration files
log_info "Backing up configuration files..."
if [[ -f .env ]]; then
  cp .env "$BACKUP_DIR/"
  log_success ".env backed up"
fi

if [[ -f config-registry/env/secrets.env.vault ]]; then
  cp config-registry/env/secrets.env.vault "$BACKUP_DIR/"
  log_success "Vault secrets backed up"
fi

# SSH keys
log_info "Backing up SSH keys..."
if [[ -d ~/.ssh ]]; then
  tar -czf "$BACKUP_DIR/ssh-keys.tar.gz" -C ~/.ssh . 2>/dev/null || true
  log_success "SSH keys backed up"
fi

# Cron jobs
log_info "Backing up cron jobs..."
crontab -l > "$BACKUP_DIR/crontab-backup.txt" 2>/dev/null || log_warn "No cron jobs found"

# System configs
log_info "Backing up system configurations..."
sudo cp /etc/netplan/*.yaml "$BACKUP_DIR/" 2>/dev/null || log_warn "No netplan configs found"

# Git repo status
log_info "Backing up git status..."
git status > "$BACKUP_DIR/git-status.txt" 2>/dev/null || true
git log -20 --oneline > "$BACKUP_DIR/git-log.txt" 2>/dev/null || true

# Summary
echo ""
log_success "Backup complete!"
log_info "Backup location: $BACKUP_DIR"
echo ""
log_info "Backup contents:"
ls -lh "$BACKUP_DIR"
echo ""
log_info "Total backup size:"
du -sh "$BACKUP_DIR"
echo ""
log_warn "IMPORTANT: Copy this backup to external storage or cloud before proceeding!"
log_info "Verify the backup with: tar -tzf $BACKUP_DIR/srv-data.tar.gz | head"

