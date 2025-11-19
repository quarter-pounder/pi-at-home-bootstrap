#!/usr/bin/env bash
set -Eeuo pipefail
trap 'log_error "Security hardening interrupted"; exit 1' INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/utils.sh"

log_info "Starting security hardening..."

if ! sudo -n true 2>/dev/null && ! sudo -v 2>/dev/null; then
  log_error "This script requires sudo access. Please ensure you have sudo privileges."
  exit 1
fi

USERNAME_VALUE="${USERNAME:-$USER}"
SSH_ALLOWED_USERS="${SSH_ALLOWED_USERS:-$USERNAME_VALUE}"
DOMAIN_VALUE="${DOMAIN:-}"
DEFAULT_EMAIL="alerts@${DOMAIN_VALUE:-local}"
EMAIL_VALUE="${EMAIL:-$DEFAULT_EMAIL}"

log_info "Hardening SSH configuration..."
sudo mkdir -p /etc/ssh/sshd_config.d
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup."$(date +%Y%m%d%H%M%S)"
sudo tee /etc/ssh/sshd_config.d/99-pi-forge-hardening.conf >/dev/null <<EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
MaxAuthTries 3
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ${SSH_ALLOWED_USERS}
EOF
if systemctl list-unit-files sshd.service >/dev/null 2>&1; then
  SSH_SERVICE="sshd"
elif systemctl list-unit-files ssh.service >/dev/null 2>&1; then
  SSH_SERVICE="ssh"
else
  log_error "Neither sshd.service nor ssh.service found; cannot restart SSH"
  exit 1
fi

sudo systemctl restart "${SSH_SERVICE}"
log_success "SSH hardening applied"

log_info "Configuring fail2ban..."
sudo mkdir -p /etc/fail2ban/jail.d
sudo tee /etc/fail2ban/jail.d/pi-forge.conf >/dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = ${EMAIL_VALUE}
sendername = Fail2Ban
sender = ${EMAIL_VALUE}

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
EOF
sudo systemctl enable fail2ban >/dev/null
sudo systemctl restart fail2ban
log_success "fail2ban configured"

log_info "Configuring unattended upgrades..."
sudo tee /etc/apt/apt.conf.d/50unattended-upgrades >/dev/null <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
sudo systemctl enable --now unattended-upgrades.service >/dev/null
log_success "Unattended upgrades configured"

log_info "Applying sysctl hardening..."
sudo tee /etc/sysctl.d/99-pi-forge-security.conf >/dev/null <<'EOF'
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.tcp_syncookies = 1
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
fs.suid_dumpable = 0
EOF
sudo sysctl -p /etc/sysctl.d/99-pi-forge-security.conf >/dev/null
log_success "Kernel parameters hardened"

log_info "Security hardening complete."

