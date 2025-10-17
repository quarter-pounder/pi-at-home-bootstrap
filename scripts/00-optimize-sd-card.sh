#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env

echo "[i] Optimizing system for SD card usage..."
echo "[!] WARNING: SD cards have limited write cycles"
echo "[i] This script will optimize the system to reduce wear on your SanDisk Extreme Pro"
echo ""

# Create tmpfs for logs and temporary files
echo "[i] Setting up tmpfs for logs and temp files..."
sudo tee -a /etc/fstab >/dev/null <<EOF

# tmpfs for logs and temp files (reduces SD card wear)
tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=1G 0 0
tmpfs /var/log tmpfs defaults,noatime,nosuid,nodev,noexec,mode=0755,size=512M 0 0
tmpfs /var/tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=256M 0 0
EOF

# Mount tmpfs immediately
sudo mount -a

# Configure logrotate to reduce log writes
echo "[i] Configuring logrotate to reduce writes..."
sudo tee /etc/logrotate.d/gitlab-optimized >/dev/null <<EOF
# Optimized logrotate for SD card
/var/log/*.log {
    daily
    missingok
    rotate 3
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        /bin/kill -HUP \`cat /var/run/rsyslogd.pid 2> /dev/null\` 2> /dev/null || true
    endscript
}
EOF

# Configure systemd journal to reduce writes
echo "[i] Configuring systemd journal for SD card..."
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/sd-card.conf >/dev/null <<EOF
[Journal]
# Reduce journal writes for SD card
SystemMaxUse=100M
SystemMaxFileSize=10M
SystemMaxFiles=5
RuntimeMaxUse=50M
RuntimeMaxFileSize=5M
RuntimeMaxFiles=3
MaxRetentionSec=1week
EOF

# Configure Docker for SD card optimization
echo "[i] Configuring Docker for SD card optimization..."
sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "data-root": "/srv/docker"
}
EOF

# Create Docker data directory
sudo mkdir -p /srv/docker
sudo chown root:root /srv/docker

# Configure GitLab for SD card optimization
echo "[i] Configuring GitLab for SD card optimization..."
if [[ -f /srv/gitlab/config/gitlab.rb ]]; then
  sudo tee -a /srv/gitlab/config/gitlab.rb >/dev/null <<EOF

# SD card optimization settings
gitlab_rails['log_level'] = 'WARN'
gitlab_rails['log_format'] = 'json'

# Reduce database writes
postgresql['checkpoint_segments'] = 32
postgresql['checkpoint_completion_target'] = 0.9
postgresql['wal_buffers'] = '16MB'
postgresql['shared_buffers'] = '256MB'

# Reduce log writes
nginx['access_log'] = '/dev/null'
nginx['error_log'] = '/dev/null'
gitlab_rails['log_level'] = 'WARN'
sidekiq['log_level'] = 'WARN'
gitlab_workhorse['log_level'] = 'warn'
registry['log_level'] = 'warn'
mattermost['log_level'] = 'WARN'
prometheus['log_level'] = 'warn'
alertmanager['log_level'] = 'warn'
node_exporter['log_level'] = 'warn'
redis['log_level'] = 'warning'
postgresql['log_min_duration_statement'] = 1000
EOF
fi

# Configure swap for better performance
echo "[i] Configuring swap for SD card..."
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Add swap to fstab
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab

# Configure swappiness for SD card
echo "[i] Configuring swappiness for SD card..."
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
echo "vm.vfs_cache_pressure=50" | sudo tee -a /etc/sysctl.conf

# Apply sysctl settings
sudo sysctl -p

# Configure cron to reduce writes
echo "[i] Configuring cron for SD card optimization..."
sudo tee /etc/cron.d/sd-card-optimization >/dev/null <<EOF
# SD card optimization cron jobs
# Clean up logs every hour
0 * * * * root find /var/log -name "*.log" -mtime +1 -delete
# Clean up tmp files every 6 hours
0 */6 * * * root find /tmp -type f -mtime +1 -delete
# Clean up Docker logs daily
0 2 * * * root find /srv/docker/containers -name "*.log" -mtime +3 -delete
EOF

echo ""
echo "[i] SD card optimization complete!"
echo ""
echo "[i] Optimizations applied:"
echo "  - tmpfs for /tmp, /var/log, /var/tmp"
echo "  - Reduced log retention and rotation"
echo "  - Docker log size limits"
echo "  - GitLab log level set to WARN"
echo "  - 2GB swap file created"
echo "  - Reduced swappiness (10)"
echo "  - Automatic cleanup cron jobs"
echo ""
echo "[!] IMPORTANT: Monitor your SD card health regularly:"
echo "    - Check wear leveling: sudo smartctl -a /dev/mmcblk0"
echo "    - Monitor disk usage: df -h"
echo "    - Check log sizes: du -sh /var/log/*"
echo ""
echo "[i] Consider migrating to NVMe when possible for better performance and longevity"
