#!/usr/bin/env bash
# NVMe Migration Utility for Raspberry Pi 5
# Description: Safely migrates from SD to NVMe with auto-cloud-init setup.
# Requirements: curl, xz-utils, pv (optional), rpi-eeprom-config
set -Eeuo pipefail
trap 'echo "[!] Error at line $LINENO"; exit 1' ERR
cd "$(dirname "$0")/.."

# Log everything to file
mkdir -p /var/log
exec > >(tee -a /var/log/nvme-migrate.log) 2>&1

source bootstrap/utils.sh

echo "[i] NVMe Migration Script"
echo "[i] Migrates Raspberry Pi 5 from SD card to NVMe boot"

require_root

# --- constants -------------------------------------------------------------
readonly MIN_IMAGE_SIZE=500000000    # 500 MB
readonly FIRMWARE_BASE_URL="https://raw.githubusercontent.com/raspberrypi/firmware/main/boot"
readonly UBUNTU_BASE_URL="https://cdimage.ubuntu.com/releases"
readonly BOOT_MNT="/mnt/boot/firmware"

# --- functions -------------------------------------------------------------

detect_latest_lts() {
 if [[ -z "${UBUNTU_VERSION:-}" ]]; then
   UBUNTU_VERSION=$(
     curl -s https://api.launchpad.net/devel/ubuntu/series |
       grep -Eo '"name": *"[0-9]{2}\.[0-9]{2}"' |
       cut -d'"' -f4 | sort -V | tail -1 || echo "24.04"
   )
   log_info "Detected Ubuntu LTS → ${UBUNTU_VERSION}"
 fi
}

confirm_device() {
 if [[ -z "${NVME_DEVICE:-}" ]]; then
   NVME_DEVICE=$(lsblk -dno NAME,TYPE | grep 'nvme.*disk' | awk '{print "/dev/"$1}' | head -1)
 fi
 if [[ -z "$NVME_DEVICE" ]]; then
   log_error "No NVMe device detected"
   log_info "Available block devices:"
   lsblk -dno NAME,TYPE,SIZE | grep disk
   exit 1
 fi

 # Verify device type
 if [[ ! "$NVME_DEVICE" =~ ^/dev/nvme ]]; then
   log_warn "Device ${NVME_DEVICE} doesn't look like NVMe (doesn't start with /dev/nvme)"
   read -rp "Continue anyway? (yes/no): " REPLY
   [[ $REPLY =~ ^yes$ ]] || { log_warn "Cancelled"; exit 0; }
 fi

 if [[ ! -b "$NVME_DEVICE" ]]; then
   log_error "Device ${NVME_DEVICE} is not a block device"
   exit 1
 fi

 local size; size=$(lsblk -no SIZE "$NVME_DEVICE")
 log_info "NVMe device → ${NVME_DEVICE} (${size})"

 read -rp "Proceed with migration to ${NVME_DEVICE}? (yes/no): " REPLY
 [[ $REPLY =~ ^yes$ ]] || { log_warn "Cancelled"; exit 0; }
}

prompt_config() {
 read -rp "Hostname [pi-forge]: " CFG_HOSTNAME
 CFG_HOSTNAME=${CFG_HOSTNAME:-pi-forge}
 read -rp "Username [pi]: " CFG_USERNAME
 CFG_USERNAME=${CFG_USERNAME:-pi}
 read -rp "SSH public key (or Enter to skip): " CFG_SSH_KEY

 # Validate SSH key format if provided
 if [[ -n "$CFG_SSH_KEY" ]]; then
   CFG_SSH_KEY=$(echo "$CFG_SSH_KEY" | xargs)  # Trim whitespace
   if [[ ! "$CFG_SSH_KEY" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp|ssh-dss|ssh-ecdsa-sk|ssh-ed25519-sk) ]]; then
     log_warn "SSH key format may be invalid (expected: ssh-rsa, ssh-ed25519, etc.)"
     read -rp "Continue anyway? (yes/no): " REPLY
     [[ $REPLY =~ ^yes$ ]] || { log_warn "Cancelled"; exit 0; }
   fi
 fi

 CFG_TIMEZONE=${CFG_TIMEZONE:-UTC}
 CFG_LOCALE=${CFG_LOCALE:-en_US.UTF-8}
}

download_file() {
 local url=$1 out=$2 desc=$3
 log_info "Downloading ${desc}..."
 curl -L --fail --retry 3 -o "$out" "$url" || { log_error "Download failed: ${desc}"; return 1; }
 [[ -s "$out" ]] || { log_error "${desc} empty"; return 1; }
 log_success "${desc} downloaded"
}

verify_sha256() {
 local file=$1 expected_hash=$2
 if [[ -z "$expected_hash" ]]; then
   log_warn "No checksum provided, skipping verification"
   return 0
 fi
 log_info "Verifying SHA256 checksum..."
 local actual_hash; actual_hash=$(sha256sum "$file" | cut -d' ' -f1)
 if [[ "$actual_hash" == "$expected_hash" ]]; then
   log_success "SHA256 checksum verified"
   return 0
 else
   log_error "SHA256 checksum mismatch!"
   log_error "Expected: ${expected_hash}"
   log_error "Got:      ${actual_hash}"
   return 1
 fi
}

generate_user_data() {
 local tmpfile=$(mktemp)
 cat >"$tmpfile" <<EOF
#cloud-config
hostname: ${CFG_HOSTNAME}
manage_etc_hosts: true
timezone: ${CFG_TIMEZONE}
locale: ${CFG_LOCALE}

users:
 - name: ${CFG_USERNAME}
   groups: [adm, sudo]
   shell: /bin/bash
   sudo: ALL=(ALL) NOPASSWD:ALL
EOF
 if [[ -n "$CFG_SSH_KEY" ]]; then
   CFG_SSH_KEY=$(echo "$CFG_SSH_KEY" | xargs)
   cat >>"$tmpfile" <<EOF
   ssh_authorized_keys:
     - ${CFG_SSH_KEY}
EOF
 fi
 cat >>"$tmpfile" <<'EOF'

ssh_pwauth: false
disable_root: true

package_update: true
package_upgrade: true
packages: [vim, git, curl, wget, htop, iotop, ncdu, tmux]
EOF
 # Trim trailing whitespace and write to final location
 sed 's/[[:space:]]*$//' "$tmpfile" > "$1"
 rm -f "$tmpfile"
}

generate_network_config() {
 cat >"$1" <<'EOF'
version: 2
ethernets:
 eth0: {dhcp4: true, optional: true}
wifis:
 wlan0:
   dhcp4: true
   optional: true
   access-points: {}
EOF
}

generate_meta_data() {
 cat >"$1" <<EOF
instance-id: ${CFG_HOSTNAME}-001
local-hostname: ${CFG_HOSTNAME}
EOF
}

cleanup() {
 set +e
 local exit_code=$?
 if [[ $exit_code -ne 0 ]]; then
   log_warn "Script exited with error code $exit_code"
 fi
 log_info "Cleaning up..."
 if mountpoint -q "$BOOT_MNT" 2>/dev/null; then
   umount -lf "$BOOT_MNT" 2>/dev/null || true
 fi
 rm -f "$IMG_FILE" "$IMG" "${IMG_FILE}.SHA256SUMS" 2>/dev/null || true
}
trap cleanup EXIT

# --- workflow --------------------------------------------------------------
detect_latest_lts
confirm_device
prompt_config

ROOT_DEV=$(findmnt -no SOURCE /)
if [[ "$ROOT_DEV" == *"${NVME_DEVICE}"* ]]; then
  log_error "Refusing to overwrite current root device (${ROOT_DEV})"
  exit 1
fi

# Detect image filename from Ubuntu release directory
log_info "Detecting Ubuntu image filename..."
IMG_FILE=$(curl -L --fail --continue-at - -s "https://cdimage.ubuntu.com/releases/${UBUNTU_VERSION}/release/" 2>/dev/null |
  grep -Eo 'ubuntu-[0-9.]+-preinstalled-server-arm64\+raspi\.img\.xz' | sort -V | tail -1)

if [[ -z "$IMG_FILE" ]]; then
  log_warn "Could not auto-detect image filename, using default"
  IMG_FILE="ubuntu-${UBUNTU_VERSION}-preinstalled-server-arm64+raspi.img.xz"
  log_info "Default filename: ${IMG_FILE}"
fi

IMG_URL="${UBUNTU_BASE_URL}/${UBUNTU_VERSION}/release/${IMG_FILE}"
SHA256SUM_URL="${UBUNTU_BASE_URL}/${UBUNTU_VERSION}/release/SHA256SUMS"
IMG="${IMG_FILE%.xz}"

# Download checksums file
SHA256SUM_FILE="${IMG_FILE}.SHA256SUMS"
log_info "Fetching SHA256 checksums..."
if ! curl -L --fail --retry 3 -s -o "$SHA256SUM_FILE" "$SHA256SUM_URL"; then
 log_warn "Failed to download checksums file, verification may be skipped"
 SHA256SUM_FILE=""
fi

# Download image (reuse if already exists)
if [[ -f "$IMG" ]]; then
 log_info "Reusing existing decompressed image: ${IMG}"
 log_info "Note: SHA256 verification skipped for decompressed image (verify .xz file instead)"
elif [[ -f "$IMG_FILE" ]]; then
 log_info "Reusing existing compressed image: ${IMG_FILE}"
 # Verify compressed image before decompressing
 if [[ -f "$SHA256SUM_FILE" ]]; then
   EXPECTED_HASH=$(grep " ${IMG_FILE}$" "$SHA256SUM_FILE" | cut -d' ' -f1)
   if [[ -n "$EXPECTED_HASH" ]]; then
     verify_sha256 "$IMG_FILE" "$EXPECTED_HASH" || { log_error "Compressed image failed verification"; exit 1; }
   else
     log_warn "Checksum for ${IMG_FILE} not found in SHA256SUMS"
   fi
 fi
 log_info "Decompressing..."
 unxz -f "$IMG_FILE"
else
 log_info "Downloading Ubuntu image: ${IMG_URL}"
 curl -L --fail --retry 5 --continue-at - --progress-bar -o "$IMG_FILE" "$IMG_URL"

 # Verify downloaded compressed image
 if [[ -f "$SHA256SUM_FILE" ]]; then
   EXPECTED_HASH=$(grep " ${IMG_FILE}$" "$SHA256SUM_FILE" | cut -d' ' -f1)
   if [[ -n "$EXPECTED_HASH" ]]; then
     verify_sha256 "$IMG_FILE" "$EXPECTED_HASH" || { log_error "Downloaded image failed verification"; rm -f "$IMG_FILE"; exit 1; }
   else
     log_warn "Checksum for ${IMG_FILE} not found in SHA256SUMS - file may be invalid"
   fi
 fi

 log_info "Decompressing..."
 unxz -f "$IMG_FILE"
fi

[[ -f "$IMG" ]] || { log_error "Image decompress failed"; exit 1; }

# Verify decompressed image size
SIZE=$(stat -c%s "$IMG")
if (( SIZE < MIN_IMAGE_SIZE )); then
 log_error "Image too small or corrupted: $((${SIZE}/1024/1024))MB (expected >$((${MIN_IMAGE_SIZE}/1024/1024))MB)"
 exit 1
fi
log_info "Image size: $((${SIZE}/1024/1024/1024))GB"

# Check available disk space before proceeding
AVAILABLE=$(df -B1 . | awk 'NR==2{print $4}')
REQUIRED=$((SIZE + 1024 * 1024 * 1024))  # Image size + 1GB buffer
if (( AVAILABLE < REQUIRED )); then
 log_error "Insufficient disk space: $((${AVAILABLE}/1024/1024/1024))GB available, need ~$((${REQUIRED}/1024/1024/1024))GB"
 exit 1
fi

log_info "Unmounting existing partitions on ${NVME_DEVICE}..."
umount "${NVME_DEVICE}"* 2>/dev/null || true
timeout 10 blkdiscard -f "$NVME_DEVICE" || log_warn "blkdiscard unsupported – continuing"

log_warn "Flashing image to ${NVME_DEVICE} (this erases everything)"
if command -v pv >/dev/null; then
 pv "$IMG" | dd of="$NVME_DEVICE" bs=4M conv=fsync status=progress
else
 dd if="$IMG" of="$NVME_DEVICE" bs=4M conv=fsync status=progress
fi
sync

log_info "Verifying write operation..."
fdisk -l "$NVME_DEVICE" || log_warn "fdisk verification failed"

log_info "Comparing first 1MB for integrity..."
if ! cmp -n 1048576 "$IMG" "$NVME_DEVICE" 2>/dev/null; then
 log_error "Integrity check failed - first 1MB mismatch"
 log_error "This may indicate:"
 log_error "  - Write error during dd operation"
 log_error "  - Device communication issue"
 log_error "  - Corrupted source image"
 log_error "Please verify the source image and device connection"
 exit 1
fi
log_success "Integrity check passed"

log_info "Refreshing partition table"
partprobe "$NVME_DEVICE" || partx -u "$NVME_DEVICE" || true
sleep 3

# Detect boot partition (handles both nvme0n1p1 and sda1 formats)
BOOT_PART="${NVME_DEVICE}p1"
[[ ! -b "$BOOT_PART" ]] && BOOT_PART="${NVME_DEVICE}1"
[[ ! -b "$BOOT_PART" ]] && { log_error "Boot partition not found"; exit 1; }

mkdir -p "$BOOT_MNT"
mount "$BOOT_PART" "$BOOT_MNT"
mountpoint -q "$BOOT_MNT" || { log_error "Failed to mount boot partition"; exit 1; }

log_info "Generating cloud-init config in ${BOOT_MNT}"
generate_user_data "$BOOT_MNT/user-data"
generate_network_config "$BOOT_MNT/network-config"
generate_meta_data "$BOOT_MNT/meta-data"

# Verify cloud-init files were written
log_info "Verifying cloud-init files..."
for f in user-data network-config meta-data; do
 if [[ ! -f "$BOOT_MNT/$f" ]]; then
   log_error "cloud-init file missing: $f"
   exit 1
 fi
 if [[ ! -s "$BOOT_MNT/$f" ]]; then
   log_error "cloud-init file is empty: $f"
   exit 1
 fi
done
log_success "cloud-init files written and verified"

if [[ ! -f "$BOOT_MNT/bcm2712-rpi-5-b.dtb" ]]; then
 log_info "Fetching Pi 5 DTB"
 if ! download_file "${FIRMWARE_BASE_URL}/bcm2712-rpi-5-b.dtb" "$BOOT_MNT/bcm2712-rpi-5-b.dtb" "Pi5 DTB"; then
   log_error "Failed to download Pi 5 DTB - boot will likely fail"
   exit 1
 fi
fi
for f in start4.elf fixup4.dat; do
 if [[ ! -f "$BOOT_MNT/$f" ]]; then
   if ! download_file "${FIRMWARE_BASE_URL}/$f" "$BOOT_MNT/$f" "$f"; then
     log_error "Failed to download firmware file: $f"
     exit 1
   fi
 fi
done

grep -q "root=LABEL=writable" "$BOOT_MNT/cmdline.txt" || \
 log_warn "cmdline.txt missing root=LABEL=writable – verify before boot"

if command -v rpi-eeprom-config >/dev/null; then
 TMP=$(mktemp)
 rpi-eeprom-config >"$TMP"
 if grep -q '^BOOT_ORDER=' "$TMP"; then
   sed -i 's/^BOOT_ORDER=.*/BOOT_ORDER=0xf416/' "$TMP"
 else
   echo "BOOT_ORDER=0xf416" >>"$TMP"
 fi
 rpi-eeprom-config --apply "$TMP"
 rm "$TMP"
 log_success "EEPROM set → NVMe-first boot (0xf416)"

 if command -v rpi-eeprom-update >/dev/null; then
   log_info "Updating EEPROM firmware..."
   rpi-eeprom-update -a || log_warn "EEPROM update failed (may need reboot)"
 fi
else
 log_warn "rpi-eeprom-config not available; set BOOT_ORDER manually"
fi

log_info "Validation summary:"
ls -lh "$BOOT_MNT" | grep -E "vmlinuz|initrd|bcm2712|start4|fixup4|config|cmdline|user-data"
blkid | grep "$(basename "$NVME_DEVICE")" || true
umount "$BOOT_MNT"
sync

echo
log_success "NVMe image prepared successfully!"
echo
cat <<'NEXT'
Next steps:
 1. sudo poweroff
 2. Remove the SD card
 3. Boot from NVMe
 4. ssh pi@<host> to verify lsblk
 5. Continue setup after cloud-init completes
NEXT
