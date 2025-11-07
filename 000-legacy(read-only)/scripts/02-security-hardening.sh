#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env

echo "[i] Hardening SSH configuration..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<EOF
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
AllowUsers ${USERNAME}
EOF

sudo systemctl restart sshd

echo "[i] Configuring fail2ban for SSH..."
sudo tee /etc/fail2ban/jail.local >/dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = ${EMAIL}
sendername = Fail2Ban

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
EOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban

echo "[i] Configuring automatic security updates..."
sudo tee /etc/apt/apt.conf.d/50unattended-upgrades >/dev/null <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

echo "[i] Hardening sysctl parameters..."
sudo tee /etc/sysctl.d/99-security.conf >/dev/null <<EOF
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

sudo sysctl -p /etc/sysctl.d/99-security.conf

echo "[i] Security hardening complete."

