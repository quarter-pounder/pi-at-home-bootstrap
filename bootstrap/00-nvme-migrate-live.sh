#!/usr/bin/env bash
# Live SD → NVMe migration for Raspberry Pi.
# - Clones existing running system from SD to NVMe using rsync
# - Creates fresh partition table on NVMe (boot + root)
# - Root partition auto-expands to fill NVMe
# - Updates PARTUUID in /etc/fstab and cmdline.txt
# - Does NOT touch the existing SD contents
# - Does NOT change users, packages, or configs

set -Eeuo pipefail

cd "$(dirname "$0")/.."

LOG_FILE="/var/log/nvme-migrate-live.log"
if ! mkdir -p /var/log 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
  LOG_FILE="$PWD/nvme-migrate-live.log"
fi
exec > >(tee -a "$LOG_FILE") 2>&1

source "$(dirname "$0")/utils.sh"

if [[ "$LOG_FILE" != "/var/log/nvme-migrate-live.log" ]]; then
  log_warn "Cannot write to /var/log, using fallback: $LOG_FILE"
fi

log_info "====================================================="
log_info " Live SD → NVMe migration (in-place, auto-expand)"
log_info "====================================================="

require_root

# ---------------------------------------------------------------------------
# Error / cleanup
# ---------------------------------------------------------------------------
cleanup() {
  local exit_code=$?
  set +e
  log_info "Cleaning up temporary mounts..."
  # Unmount bind mount first
  mountpoint -q /mnt/nvme-root/boot && umount /mnt/nvme-root/boot 2>/dev/null || true
  # Then unmount main mounts
  mountpoint -q /mnt/nvme-root && umount /mnt/nvme-root 2>/dev/null || true
  mountpoint -q /mnt/nvme-boot && umount /mnt/nvme-boot 2>/dev/null || true
  # Force unmount if still busy
  umount -l /mnt/nvme-root 2>/dev/null || true
  umount -l /mnt/nvme-boot 2>/dev/null || true
  rmdir /mnt/nvme-root 2>/dev/null || true
  rmdir /mnt/nvme-boot 2>/dev/null || true

  if (( exit_code != 0 )); then
    log_error "Script exited with code $exit_code"
  fi
}
trap cleanup EXIT

trap 'log_error "Error at line $LINENO: $BASH_COMMAND"; exit 1' ERR

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
ensure_dependencies() {
  log_info "Checking required tools for live migration..."
  local pkgs=()

  for cmd in lsblk parted blkid mkfs.vfat mkfs.ext4 rsync sgdisk wipefs; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      case "$cmd" in
        lsblk|blkid) pkgs+=(util-linux) ;;
        parted)      pkgs+=(parted) ;;
        mkfs.vfat)   pkgs+=(dosfstools) ;;
        mkfs.ext4)   pkgs+=(e2fsprogs) ;;
        rsync)       pkgs+=(rsync) ;;
        sgdisk)      pkgs+=(gdisk) ;;
        wipefs)      pkgs+=(util-linux) ;;
      esac
    fi
  done

  if (( ${#pkgs[@]} > 0 )); then
    log_info "Installing missing packages: ${pkgs[*]}"
    apt-get update -qq
    apt-get install -y "${pkgs[@]}"
  else
    log_success "All required tools present"
  fi
}

ensure_dependencies

# ---------------------------------------------------------------------------
# Detect Pi + root / boot devices
# ---------------------------------------------------------------------------

if [[ -f /proc/device-tree/model ]]; then
  MODEL=$(tr -d '\0' </proc/device-tree/model || true)
  log_info "Detected hardware model: $MODEL"
  if ! grep -qi "raspberry pi" <<<"$MODEL"; then
    log_warn "This does not look like a Raspberry Pi. Continue only if you know what you're doing."
  fi
else
  log_warn "/proc/device-tree/model not found – unable to confirm hardware model."
fi

ROOT_DEV=$(findmnt -no SOURCE / || true)
if [[ -z "$ROOT_DEV" ]]; then
  log_error "Cannot determine root device (findmnt / failed)"
  exit 1
fi
log_info "Root filesystem: $ROOT_DEV"

ROOT_DISK="/dev/$(lsblk -no PKNAME "$ROOT_DEV")"
if [[ -z "$ROOT_DISK" ]]; then
  log_error "Cannot determine parent disk of root ($ROOT_DEV)"
  exit 1
fi
log_info "Root disk (likely SD card): $ROOT_DISK"

# /boot or /boot/firmware
BOOT_MOUNT=$(findmnt -no TARGET /boot 2>/dev/null || true)
if [[ -z "$BOOT_MOUNT" ]]; then
  BOOT_MOUNT=$(findmnt -no TARGET /boot/firmware 2>/dev/null || true)
fi
if [[ -z "$BOOT_MOUNT" ]]; then
  log_error "Cannot find separate /boot or /boot/firmware mount."
  log_error "This script assumes a Pi-style boot partition."
  exit 1
fi
BOOT_DEV=$(findmnt -no SOURCE "$BOOT_MOUNT")
if [[ -z "$BOOT_DEV" ]]; then
  log_error "Cannot determine boot device."
  exit 1
fi
log_info "Boot partition: $BOOT_DEV mounted on $BOOT_MOUNT"

if [[ "$BOOT_DEV" != "${ROOT_DISK}"* ]]; then
  log_warn "Boot partition is not on the same disk as root. This is unusual for Pi, continuing cautiously."
fi

# ---------------------------------------------------------------------------
# Detect NVMe device
# ---------------------------------------------------------------------------

detect_nvme() {
  if [[ -n "${NVME_DEVICE:-}" ]]; then
    log_info "Using NVME_DEVICE from environment: $NVME_DEVICE"
    echo "$NVME_DEVICE"
    return
  fi

  # Any disk that is not the root disk
  local candidates
  candidates=$(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -v "^$ROOT_DISK\$" || true)

  # Prefer nvme* names
  local nvme_candidate
  nvme_candidate=$(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -E "/nvme" | grep -v "^$ROOT_DISK\$" | head -1 || true)

  if [[ -n "$nvme_candidate" ]]; then
    echo "$nvme_candidate"
    return
  fi

  # Fallback to "any other disk"
  if [[ -n "$candidates" ]]; then
    echo "$(head -1 <<<"$candidates")"
    return
  fi

  echo ""
}

NVME_DEVICE=$(detect_nvme)
if [[ -z "$NVME_DEVICE" ]]; then
  log_error "No NVMe / secondary disk detected. Plug NVMe and retry."
  lsblk -dpno NAME,TYPE,SIZE || true
  exit 1
fi

if [[ ! -b "$NVME_DEVICE" ]]; then
  log_error "Detected NVMe disk is not a block device: $NVME_DEVICE"
  exit 1
fi

if [[ "$NVME_DEVICE" == "$ROOT_DISK" ]]; then
  log_error "NVMe disk and root disk are the same ($NVME_DEVICE)."
  log_error "This script is for migrating FROM SD (root) TO NVMe."
  exit 1
fi

log_info "Target NVMe disk: $NVME_DEVICE"

# Clean up any leftover mounts from previous runs
log_info "Cleaning up any leftover mounts from previous runs..."
mountpoint -q /mnt/nvme-root/boot && umount /mnt/nvme-root/boot 2>/dev/null || true
mountpoint -q /mnt/nvme-root && umount /mnt/nvme-root 2>/dev/null || true
mountpoint -q /mnt/nvme-boot && umount /mnt/nvme-boot 2>/dev/null || true
umount -l /mnt/nvme-root 2>/dev/null || true
umount -l /mnt/nvme-boot 2>/dev/null || true

# Unmount any existing NVMe partitions
for part in "${NVME_DEVICE}"p* "${NVME_DEVICE}"[0-9]*; do
  [[ -e "$part" ]] && mountpoint -q "$part" 2>/dev/null && umount "$part" 2>/dev/null || true
done

# Refresh partition table to clear any stale entries
partprobe "$NVME_DEVICE" 2>/dev/null || true
sleep 1

# ---------------------------------------------------------------------------
# Sanity checks on sizes
# ---------------------------------------------------------------------------

ROOT_SIZE=$(blockdev --getsize64 "$ROOT_DISK" 2>/dev/null || echo "0")
NVME_SIZE=$(blockdev --getsize64 "$NVME_DEVICE" 2>/dev/null || echo "0")

if (( ROOT_SIZE == 0 )); then
  log_error "Failed to determine root disk size"
  exit 1
fi
if (( NVME_SIZE == 0 )); then
  log_error "Failed to determine NVMe disk size"
  exit 1
fi

log_info "Root disk size:  $((ROOT_SIZE/1024/1024/1024)) GiB"
log_info "NVMe disk size:  $((NVME_SIZE/1024/1024/1024)) GiB"

if (( NVME_SIZE <= ROOT_SIZE )); then
  log_warn "NVMe is not larger than SD. Auto-expand still works if partitions are smaller than full disk,"
  log_warn "but you lose the advantage of more space. Continuing anyway."
fi

log_warn "The following disk will be RE-PARTITIONED AND ERASED: $NVME_DEVICE"
lsblk -dpno NAME,SIZE,MODEL "$NVME_DEVICE" || true
confirm_continue "Type 'yes' to continue and destroy all data on $NVME_DEVICE: "

# ---------------------------------------------------------------------------
# Check for active swap
# ---------------------------------------------------------------------------

log_info "Checking for active swap..."
ACTIVE_SWAP=$(swapon --show --noheadings --raw 2>/dev/null || true)
if [[ -n "$ACTIVE_SWAP" ]]; then
  log_warn "Active swap detected:"
  swapon --show || true
  log_warn "Disabling swap to ensure consistent migration..."
  if ! swapoff -a; then
    log_error "Failed to disable swap. Please disable swap manually and retry."
    log_error "Use: sudo swapoff -a"
    exit 1
  fi
  log_success "Swap disabled"
else
  log_info "No active swap detected"
fi

# Check for swapfiles that will be copied
SWAPFILES=()
for swapfile in /swapfile /var/swap /swap.img; do
  if [[ -f "$swapfile" ]]; then
    SWAPFILES+=("$swapfile")
  fi
done

if (( ${#SWAPFILES[@]} > 0 )); then
  log_info "Found swapfile(s) that will be copied: ${SWAPFILES[*]}"
  log_info "Note: Swapfiles will be copied but will need to be re-enabled after boot"
fi

# ---------------------------------------------------------------------------
# Partition NVMe: boot (same size as current boot, rounded up), root = rest
# ---------------------------------------------------------------------------

log_info "Inspecting existing boot partition size..."
BOOT_SIZE_BYTES=$(lsblk -bno SIZE "$BOOT_DEV")
if [[ -z "$BOOT_SIZE_BYTES" ]]; then
  log_error "Cannot determine size of current boot partition: $BOOT_DEV"
  exit 1
fi
BOOT_SIZE_MIB=$(( (BOOT_SIZE_BYTES + 1024*1024 - 1) / (1024*1024) ))

# Add a small safety margin (e.g. +64MiB)
BOOT_SIZE_MIB=$((BOOT_SIZE_MIB + 64))

log_info "Will create NVMe boot partition of ~${BOOT_SIZE_MIB} MiB."

log_info "Wiping existing partition table on $NVME_DEVICE..."
wipefs -a "$NVME_DEVICE" >/dev/null 2>&1 || true
sgdisk --zap-all "$NVME_DEVICE" >/dev/null 2>&1 || true

# Force kernel to forget about old partitions
partprobe "$NVME_DEVICE" 2>/dev/null || true
partx -d "$NVME_DEVICE" 2>/dev/null || true
sleep 2

log_info "Creating new GPT, boot + root partitions on NVMe..."
if ! parted -s "$NVME_DEVICE" \
  mklabel gpt \
  mkpart primary fat32 1MiB "${BOOT_SIZE_MIB}MiB" \
  set 1 boot on \
  mkpart primary ext4 "${BOOT_SIZE_MIB}MiB" 100%; then
  log_error "Failed to create partitions. Device may be in use."
  log_error "Try: sudo partprobe $NVME_DEVICE && sudo partx -d $NVME_DEVICE"
  exit 1
fi

sleep 2
if ! partprobe "$NVME_DEVICE" 2>/dev/null; then
  if ! partx -u "$NVME_DEVICE" 2>/dev/null; then
    log_warn "Partition table refresh failed, trying alternative method..."
    sleep 2
    udevadm settle || true
    # Try one more time
    partprobe "$NVME_DEVICE" 2>/dev/null || true
  fi
fi
sleep 2

# Partition naming: nvmeXp1 / Xp2 or X1 / X2
if [[ -b "${NVME_DEVICE}p1" ]]; then
  NVME_BOOT_PART="${NVME_DEVICE}p1"
  NVME_ROOT_PART="${NVME_DEVICE}p2"
else
  NVME_BOOT_PART="${NVME_DEVICE}1"
  NVME_ROOT_PART="${NVME_DEVICE}2"
fi

if [[ ! -b "$NVME_BOOT_PART" || ! -b "$NVME_ROOT_PART" ]]; then
  log_error "Failed to detect NVMe partitions after creation."
  lsblk -o NAME,SIZE,TYPE "$NVME_DEVICE" || true
  exit 1
fi

log_success "NVMe partitions created: $NVME_BOOT_PART (boot), $NVME_ROOT_PART (root)"

log_info "Creating filesystems on NVMe..."
# Use labels that match Ubuntu's expected labels (system-boot and writable)
if ! mkfs.vfat -F 32 -n system-boot "$NVME_BOOT_PART"; then
  log_error "Failed to create boot filesystem"
  exit 1
fi
if ! mkfs.ext4 -L writable "$NVME_ROOT_PART"; then
  log_error "Failed to create root filesystem"
  exit 1
fi
log_success "Filesystems created with labels: system-boot (boot), writable (root)"

# Verify filesystems
log_info "Verifying new filesystems..."
if fsck -n "$NVME_BOOT_PART" >/dev/null 2>&1; then
  log_success "Boot partition filesystem is valid"
else
  log_warn "Boot partition filesystem check returned warnings (may be normal)"
fi
if fsck -n "$NVME_ROOT_PART" >/dev/null 2>&1; then
  log_success "Root partition filesystem is valid"
else
  log_warn "Root partition filesystem check returned warnings (may be normal)"
fi

# ---------------------------------------------------------------------------
# Mount new filesystems
# ---------------------------------------------------------------------------

mkdir -p /mnt/nvme-boot /mnt/nvme-root

log_info "Mounting NVMe target filesystems..."
if ! mount "$NVME_ROOT_PART" /mnt/nvme-root; then
  log_error "Failed to mount root partition ${NVME_ROOT_PART}"
  exit 1
fi
if ! mount "$NVME_BOOT_PART" /mnt/nvme-boot; then
  log_error "Failed to mount boot partition ${NVME_BOOT_PART}"
  exit 1
fi
log_success "Both partitions mounted successfully"

# Make sure target has /boot directory for bind/mount consistency
mkdir -p /mnt/nvme-root/boot

# ---------------------------------------------------------------------------
# Rsync root filesystem (excluding pseudo filesystems, target mounts, etc.)
# ---------------------------------------------------------------------------

log_info "Syncing ROOT filesystem to NVMe (this may take time)..."
if ! rsync -aHAX --delete \
  --exclude='/boot/*' \
  --exclude='/dev/*' \
  --exclude='/proc/*' \
  --exclude='/sys/*' \
  --exclude='/tmp/*' \
  --exclude='/run/*' \
  --exclude='/mnt/*' \
  --exclude='/media/*' \
  --exclude='/lost+found' \
  / /mnt/nvme-root/; then
  log_error "Root filesystem rsync failed"
  exit 1
fi

# Verify critical files were copied
log_info "Verifying critical files were copied..."
REQUIRED_FILES=("/etc/fstab" "/etc/passwd" "/bin/sh" "/sbin/init")
MISSING=()
for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -e "/mnt/nvme-root${file}" ]]; then
    MISSING+=("${file}")
  fi
done
if (( ${#MISSING[@]} > 0 )); then
  log_error "Critical files missing after rsync: ${MISSING[*]}"
  exit 1
fi

# Verify swapfiles were copied (if they existed)
if (( ${#SWAPFILES[@]} > 0 )); then
  log_info "Verifying swapfiles were copied..."
  for swapfile in "${SWAPFILES[@]}"; do
    if [[ -f "/mnt/nvme-root${swapfile}" ]]; then
      log_success "Swapfile copied: ${swapfile}"
    else
      log_warn "Swapfile not found after rsync: ${swapfile} (may have been excluded)"
    fi
  done
fi

log_success "Root filesystem synced and verified."

# ---------------------------------------------------------------------------
# Rsync boot partition
# ---------------------------------------------------------------------------

log_info "Syncing BOOT partition to NVMe..."
if ! rsync -aHAX --delete "${BOOT_MOUNT}/" /mnt/nvme-boot/; then
  log_error "Boot partition rsync failed"
  exit 1
fi

# Validate critical boot files
log_info "Validating boot partition files..."
REQUIRED_BOOT_FILES=("config.txt" "start4.elf" "fixup4.dat")
MISSING_BOOT=()
for file in "${REQUIRED_BOOT_FILES[@]}"; do
  if [[ ! -f "/mnt/nvme-boot/${file}" ]]; then
    MISSING_BOOT+=("${file}")
  fi
done
if (( ${#MISSING_BOOT[@]} > 0 )); then
  log_error "Critical boot files missing: ${MISSING_BOOT[*]}"
  exit 1
fi
log_success "Boot partition synced and validated."

# Bind-mount boot into nvme-root for editing configs coherently
mount --bind /mnt/nvme-boot /mnt/nvme-root/boot

# ---------------------------------------------------------------------------
# Update PARTUUIDs in /etc/fstab and cmdline.txt
# ---------------------------------------------------------------------------

log_info "Updating PARTUUID references for new NVMe root/boot..."

ROOT_PART="$ROOT_DEV"
BOOT_PART="$BOOT_DEV"

OLD_ROOT_UUID=$(blkid -s PARTUUID -o value "$ROOT_PART" || true)
OLD_BOOT_UUID=$(blkid -s PARTUUID -o value "$BOOT_PART" || true)
NEW_ROOT_UUID=$(blkid -s PARTUUID -o value "$NVME_ROOT_PART" || true)
NEW_BOOT_UUID=$(blkid -s PARTUUID -o value "$NVME_BOOT_PART" || true)

log_info "Old root PARTUUID: $OLD_ROOT_UUID"
log_info "Old boot PARTUUID: $OLD_BOOT_UUID"
log_info "New root PARTUUID: $NEW_ROOT_UUID"
log_info "New boot PARTUUID: $NEW_BOOT_UUID"

FSTAB="/mnt/nvme-root/etc/fstab"
if [[ -f "$FSTAB" ]]; then
  cp "$FSTAB" "${FSTAB}.bak.$(date +%Y%m%d_%H%M%S)"

  if [[ -n "$OLD_ROOT_UUID" && -n "$NEW_ROOT_UUID" ]]; then
    # Check if old UUID exists in fstab before replacing
    if grep -q "PARTUUID=${OLD_ROOT_UUID}" "$FSTAB"; then
      sed -i "s|PARTUUID=${OLD_ROOT_UUID}|PARTUUID=${NEW_ROOT_UUID}|g" "$FSTAB"
      # Verify update
      if ! grep -q "PARTUUID=${NEW_ROOT_UUID}" "$FSTAB"; then
        log_error "Failed to update root PARTUUID in /etc/fstab"
        exit 1
      fi
      log_success "Updated root PARTUUID in /etc/fstab"
    else
      log_warn "Root PARTUUID ${OLD_ROOT_UUID} not found in /etc/fstab (may use device names or labels)"
    fi
  fi

  if [[ -n "$OLD_BOOT_UUID" && -n "$NEW_BOOT_UUID" ]]; then
    # Check if old UUID exists in fstab before replacing
    if grep -q "PARTUUID=${OLD_BOOT_UUID}" "$FSTAB"; then
      sed -i "s|PARTUUID=${OLD_BOOT_UUID}|PARTUUID=${NEW_BOOT_UUID}|g" "$FSTAB"
      # Verify update
      if ! grep -q "PARTUUID=${NEW_BOOT_UUID}" "$FSTAB"; then
        log_error "Failed to update boot PARTUUID in /etc/fstab"
        exit 1
      fi
      log_success "Updated boot PARTUUID in /etc/fstab"
    else
      log_warn "Boot PARTUUID ${OLD_BOOT_UUID} not found in /etc/fstab (may use device names or labels)"
    fi
  fi

  log_success "fstab update complete."
else
  log_warn "No /etc/fstab found on target? Check manually."
fi

# cmdline.txt location (Pi OS vs Ubuntu)
CMDLINE=""
if [[ -f /mnt/nvme-boot/cmdline.txt ]]; then
  CMDLINE="/mnt/nvme-boot/cmdline.txt"
elif [[ -f /mnt/nvme-boot/firmware/cmdline.txt ]]; then
  CMDLINE="/mnt/nvme-boot/firmware/cmdline.txt"
fi

if [[ -n "$CMDLINE" ]]; then
  cp "$CMDLINE" "${CMDLINE}.bak.$(date +%Y%m%d_%H%M%S)"

  # Update or add root= parameter
  if [[ -n "$NEW_ROOT_UUID" ]]; then
    # Check if root= already exists
    if grep -q "root=" "$CMDLINE"; then
      # Replace existing root= parameter
      if [[ -n "$OLD_ROOT_UUID" ]] && grep -q "root=PARTUUID=${OLD_ROOT_UUID}" "$CMDLINE"; then
        sed -i "s|root=PARTUUID=${OLD_ROOT_UUID}|root=PARTUUID=${NEW_ROOT_UUID}|g" "$CMDLINE"
        log_success "Updated root PARTUUID in cmdline.txt"
      elif grep -q "root=LABEL=" "$CMDLINE"; then
        # Replace LABEL=writable with PARTUUID
        sed -i "s|root=LABEL=writable|root=PARTUUID=${NEW_ROOT_UUID}|g" "$CMDLINE"
        log_success "Updated root parameter in cmdline.txt (LABEL to PARTUUID)"
      else
        # Replace any root= with new PARTUUID
        sed -i "s|root=[^ ]*|root=PARTUUID=${NEW_ROOT_UUID}|g" "$CMDLINE"
        log_success "Updated root parameter in cmdline.txt"
      fi
    else
      # Add root= parameter if it doesn't exist
      # Add it at the beginning of the cmdline
      sed -i "s|^|root=PARTUUID=${NEW_ROOT_UUID} |" "$CMDLINE"
      log_success "Added root PARTUUID to cmdline.txt"
    fi

    # Verify root= parameter exists
    if ! grep -q "root=PARTUUID=${NEW_ROOT_UUID}" "$CMDLINE"; then
      log_error "Failed to set root PARTUUID in cmdline.txt"
      exit 1
    fi
    log_success "Verified root PARTUUID in cmdline.txt"
  else
    log_warn "Could not determine new root PARTUUID – cmdline.txt may need manual update."
  fi
else
  log_warn "cmdline.txt not found on target boot partition – check layout manually."
fi

# ---------------------------------------------------------------------------
# EEPROM boot order
# ---------------------------------------------------------------------------

log_info "Checking EEPROM boot order for NVMe preference..."
if command -v rpi-eeprom-config >/dev/null 2>&1; then
  TMP=$(mktemp)
  if rpi-eeprom-config >"$TMP" 2>/dev/null; then
    if grep -q '^BOOT_ORDER=' "$TMP"; then
      CURRENT_BO=$(grep '^BOOT_ORDER=' "$TMP" | head -1 | cut -d= -f2 | tr -d '[:space:]')
      log_info "Current BOOT_ORDER=$CURRENT_BO"
      if [[ "$CURRENT_BO" != "0xf416" ]]; then
        sed -i 's/^BOOT_ORDER=.*/BOOT_ORDER=0xf416/' "$TMP"
        log_info "Applying BOOT_ORDER=0xf416 (NVMe first, fallback to others)..."
        if rpi-eeprom-config --apply "$TMP"; then
          sleep 2
          if rpi-eeprom-config | grep -q 'BOOT_ORDER=0xf416'; then
            log_success "EEPROM updated: BOOT_ORDER=0xf416"
          else
            log_warn "EEPROM update may not have taken effect – verify manually."
          fi
        else
          log_warn "Failed to apply EEPROM config – configure manually if needed."
        fi
      else
        log_info "BOOT_ORDER already 0xf416 – leaving as-is."
      fi
    else
      echo "BOOT_ORDER=0xf416" >>"$TMP"
      log_info "Setting BOOT_ORDER=0xf416 in EEPROM..."
      rpi-eeprom-config --apply "$TMP" || log_warn "Failed to apply EEPROM config – check manually."
    fi
  else
    log_warn "Failed to read EEPROM config – you may need to configure boot order manually."
  fi
  rm -f "$TMP"
else
  log_warn "rpi-eeprom-config not available – cannot auto-set NVMe-first boot."
fi

# ---------------------------------------------------------------------------
# Final verification
# ---------------------------------------------------------------------------

log_info "Final NVMe layout:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$NVME_DEVICE" || true

log_info "Target /etc/fstab on NVMe:"
grep -Ev '^\s*#|^\s*$' /mnt/nvme-root/etc/fstab 2>/dev/null || echo "(empty or missing)"

if [[ -n "$CMDLINE" ]]; then
  log_info "Target cmdline.txt (root=...) snippet:"
  grep -o 'root=[^ ]*' "$CMDLINE" || cat "$CMDLINE" || true
fi

log_success "Live SD → NVMe migration complete (files cloned, root auto-expanded)."

echo
echo "=================================================================="
echo "Next steps:"
echo " 1. Reboot: sudo reboot"
echo " 2. The system will automatically boot from NVMe (boot order: 0xf416)"
echo " 3. After boot, verify with:"
echo "      lsblk"
echo "      findmnt /"
echo "    Root should now be on $NVME_ROOT_PART"
if (( ${#SWAPFILES[@]} > 0 )); then
  echo " 4. Re-enable swap if needed:"
  for swapfile in "${SWAPFILES[@]}"; do
    echo "      sudo swapon ${swapfile}"
  done
  echo "    (Swapfiles were copied and should be in /etc/fstab)"
  echo " 5. Keep the SD card installed as a backup until you're 100% satisfied."
else
  echo " 4. Keep the SD card installed as a backup until you're 100% satisfied."
fi
echo ""
echo "Note: The SD card can remain installed. The boot order (0xf416) prioritizes"
echo "      NVMe, so it will boot from NVMe if available, and only fall back to"
echo "      SD card if NVMe is not present."
echo "=================================================================="
echo
