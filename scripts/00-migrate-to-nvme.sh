#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env
detect_latest_lts
confirm_device

# Constants
readonly MIN_IMAGE_SIZE=500000000  # 500MB minimum image size
readonly FIRMWARE_BASE_URL="https://raw.githubusercontent.com/raspberrypi/firmware/main/boot"
readonly UBUNTU_BASE_URL="https://cdimage.ubuntu.com/releases"

# Download files with error handling
download_file() {
  local url="$1"
  local output="$2"
  local description="$3"

  echo "[i] Downloading ${description}..."
  if ! wget -O "${output}" "${url}" 2>/dev/null; then
    echo "[!] Failed to download ${description} from ${url}"
    return 1
  fi

  if [[ ! -s "${output}" ]]; then
    echo "[!] Downloaded ${description} is empty"
    return 1
  fi

  echo "[OK] Successfully downloaded ${description}"
  return 0
}

# Cleanup on exit
cleanup() {
  set +e
  local exit_code=$?
  echo "[i] Cleaning up..."

  if mountpoint -q /mnt/boot; then
    sudo umount /mnt/boot 2>/dev/null || true
  fi

  rm -f "${IMG_FILE}" "${IMG}" 2>/dev/null || true

  if [[ $exit_code -eq 0 ]]; then
    echo "[i] Migration completed successfully."
  else
    echo "[!] Migration aborted with exit code $exit_code"
  fi

  exit $exit_code
}

trap cleanup EXIT

IMG_FILE="ubuntu-${UBUNTU_VERSION}-preinstalled-server-arm64+raspi.img.xz"
IMG_URL=${UBUNTU_IMG_URL:-"${UBUNTU_BASE_URL}/${UBUNTU_VERSION}/release/${IMG_FILE}"}
IMG="${IMG_FILE%.xz}"  # Initialize early for cleanup function

# Check disk space before download
AVAILABLE_SPACE=$(($(df . | awk 'NR==2 {print $4}') * 1024))  # Convert KB to bytes
REQUIRED_SPACE=$((MIN_IMAGE_SIZE * 2))
if [[ ${AVAILABLE_SPACE} -lt ${REQUIRED_SPACE} ]]; then
  echo "[!] Insufficient disk space. Available: $((${AVAILABLE_SPACE} / 1024 / 1024))MB, Required: $((${REQUIRED_SPACE} / 1024 / 1024))MB"
  exit 1
fi

echo "[i] Downloading Ubuntu ${UBUNTU_VERSION} image..."
echo "[i] URL: ${IMG_URL}"
echo "[i] Available space: $((${AVAILABLE_SPACE} / 1024 / 1024))MB"
curl -L --retry 5 --continue-at - -o "${IMG_FILE}" "${IMG_URL}"

echo "[i] Verifying download..."
if [[ ! -f "${IMG_FILE}" ]]; then
  echo "[!] Download failed - file not found"
  exit 1
fi

FILE_SIZE=$(stat -c%s "${IMG_FILE}")
echo "[i] Downloaded size: $((${FILE_SIZE} / 1024 / 1024))MB"
if [[ ${FILE_SIZE} -lt ${MIN_IMAGE_SIZE} ]]; then
  echo "[!] Download appears truncated (${FILE_SIZE} bytes, minimum expected: ${MIN_IMAGE_SIZE})"
  exit 1
fi

# Prevent accidental self-overwrite
if mount | grep -q "on / "; then
  ROOT_DEVICE=$(findmnt -no SOURCE /)
  if [[ "$ROOT_DEVICE" == *"${NVME_DEVICE}"* ]]; then
    echo "[!] Refusing to overwrite the current root device: $ROOT_DEVICE"
    exit 1
  fi
fi

# Handle partial decompression
if [[ -f "${IMG}" && $(stat -c%s "${IMG}") -lt ${MIN_IMAGE_SIZE} ]]; then
  echo "[!] Detected partial image (${IMG}), removing..."
  rm -f "${IMG}"
fi

# Reuse decompressed image if present
if [[ -f "${IMG}" ]]; then
  echo "[i] Reusing existing decompressed image: ${IMG}"
else
  echo "[i] Decompressing image..."
  unxz -f "${IMG_FILE}"
fi

echo "[i] Writing image to ${NVME_DEVICE}..."
echo "[!] WARNING: This will erase all data on ${NVME_DEVICE}"

# Verify NVMe device exists and is writable
if [[ ! -b "${NVME_DEVICE}" ]]; then
  echo "[!] Error: NVMe device ${NVME_DEVICE} not found"
  exit 1
fi

# Skip if device already mounted
if mount | grep -q "${NVME_DEVICE}p1"; then
  echo "[i] ${NVME_DEVICE} already mounted — skipping flash."
  exit 0
fi

# Unmount any existing partitions
sudo umount "${NVME_DEVICE}"* 2>/dev/null || true

# Reset NVMe drive if corrupted
echo "[i] Checking NVMe drive state..."
if [[ $(lsblk -no SIZE "${NVME_DEVICE}") == "0B" ]]; then
  echo "[!] NVMe drive appears corrupted (0B size), attempting reset..."

  # Try to reset the drive
  echo "[i] Resetting NVMe drive..."
  sudo nvme reset "${NVME_DEVICE}" 2>/dev/null || true
  sleep 2

  # Check if reset worked
  if [[ $(lsblk -no SIZE "${NVME_DEVICE}") == "0B" ]]; then
    echo "[!] NVMe reset failed, trying power cycle..."
    echo "[i] Please power cycle the Pi or reconnect the NVMe adapter"
    echo "[i] Then run this script again"
    exit 1
  else
    echo "[OK] NVMe drive reset successful"
  fi
fi

# Discard existing data
echo "[i] Discarding existing data..."
sudo blkdiscard "${NVME_DEVICE}" || true

# Write the image (use pv if available)
echo "[i] Writing image (this may take several minutes)..."
if command -v pv >/dev/null; then
  if ! pv "${IMG}" | sudo dd of="${NVME_DEVICE}" bs=4M conv=fsync; then
    echo "[!] Image write failed with I/O error"
    exit 1
  fi
else
  if ! sudo dd if="${IMG}" of="${NVME_DEVICE}" bs=4M status=progress conv=fsync; then
    echo "[!] Image write failed with I/O error"
    exit 1
  fi
fi

echo "[i] Verifying write..."
sync
echo "[i] Image write completed"

# Mount boot partition safely
if mountpoint -q /mnt/boot; then
  echo "[i] Unmounting stale /mnt/boot..."
  sudo umount /mnt/boot || true
fi
sudo mkdir -p /mnt/boot
sudo mount "${NVME_DEVICE}p1" /mnt/boot

# Inject cloud-init templates
echo "[i] Injecting cloud-init templates..."
envsubst < cloudinit/user-data.template | sudo tee /mnt/boot/user-data >/dev/null
envsubst < cloudinit/network-config.template | sudo tee /mnt/boot/network-config >/dev/null
envsubst < cloudinit/meta-data.template | sudo tee /mnt/boot/meta-data >/dev/null

# Preserve entire bootstrap directory for post-boot setup
echo "[i] Preserving bootstrap directory for post-boot setup..."
sudo tar -czf /mnt/boot/bootstrap-backup.tar.gz -C .. pi-at-home-bootstrap

# Create a script to restore bootstrap directory and run setup after boot
cat << 'EOF' | sudo tee /mnt/boot/restore-bootstrap.sh >/dev/null
#!/bin/bash
# Restore bootstrap directory and run setup after boot
if [[ -f /boot/bootstrap-backup.tar.gz ]]; then
  # Extract bootstrap directory
  cd /home/$(logname)
  tar -xzf /boot/bootstrap-backup.tar.gz
  chown -R $(logname):$(logname) pi-at-home-bootstrap

  # Run the setup scripts
  cd pi-at-home-bootstrap
  chmod +x scripts/*.sh

  # Run setup scripts in order
  ./scripts/01-post-boot-setup.sh
  ./scripts/02-security-hardening.sh
  ./scripts/03-install-docker.sh
  ./scripts/04-setup-gitlab.sh
  ./scripts/05-register-runner.sh
  ./scripts/06-setup-monitoring.sh

  # Clean up
  rm -f /boot/bootstrap-backup.tar.gz
  rm -f /boot/restore-bootstrap.sh
fi
EOF
sudo chmod +x /mnt/boot/restore-bootstrap.sh

# Ensure cmdline.txt exists
if [[ ! -f "/mnt/boot/cmdline.txt" ]]; then
  echo "[i] Creating missing cmdline.txt..."
  echo "console=serial0,115200 console=tty1 root=LABEL=writable rootfstype=ext4 rootwait fixrtc" | sudo tee /mnt/boot/cmdline.txt >/dev/null
fi

# Ensure tools for firmware fetch
if ! command -v wget >/dev/null 2>&1; then
  echo "[i] Installing wget..."
  sudo apt-get update -y && sudo apt-get install -y wget
fi

# Ubuntu 25.10+ firmware integrity checks
echo "[i] Checking Ubuntu 25.10-style firmware layout..."
BOOT_SRC="/mnt/boot"

OS_PREFIX=""
if [[ -f "${BOOT_SRC}/config.txt" ]]; then
  OS_PREFIX=$(grep -Po '^(?i)os_prefix=\K.*' "${BOOT_SRC}/config.txt" | tail -1 || true)
fi
echo "[i] Detected os_prefix: ${OS_PREFIX:-<none>}"

if [[ -n "${OS_PREFIX}" ]]; then
  echo "[i] Detected Ubuntu 25.10+ style boot (os_prefix=${OS_PREFIX})"
  sudo mkdir -p "${BOOT_SRC}/${OS_PREFIX}"

  # Check if kernel/initrd exist in the image
  echo "[i] Checking for kernel/initrd in image..."
  if [[ -f "${BOOT_SRC}/${OS_PREFIX}vmlinuz" && -f "${BOOT_SRC}/${OS_PREFIX}initrd.img" ]]; then
    echo "[OK] Kernel and initrd found in image"
  else
    echo "[!] Missing kernel/initrd - checking if they exist elsewhere..."

    # List all files in boot partition for debugging
    echo "[i] Files in boot partition:"
    ls -la "${BOOT_SRC}/" | head -20

    # Check what's in the current directory
    if [[ -d "${BOOT_SRC}/current" ]]; then
      echo "[i] Files in current directory:"
      ls -la "${BOOT_SRC}/current/" | head -10
    fi

    # Look for kernel/initrd in other locations
    for kernel_path in "${BOOT_SRC}/vmlinuz" "${BOOT_SRC}/vmlinuz-*" "${BOOT_SRC}/current/vmlinuz" "${BOOT_SRC}/current/vmlinuz-*"; do
      if [[ -f "${kernel_path}" ]]; then
        echo "[i] Found kernel at ${kernel_path}, copying to ${OS_PREFIX} location..."
        sudo cp "${kernel_path}" "${BOOT_SRC}/${OS_PREFIX}vmlinuz" 2>/dev/null || true
        break
      fi
    done

    for initrd_path in "${BOOT_SRC}/initrd.img" "${BOOT_SRC}/initrd.img-*" "${BOOT_SRC}/current/initrd.img" "${BOOT_SRC}/current/initrd.img-*"; do
      if [[ -f "${initrd_path}" ]]; then
        echo "[i] Found initrd at ${initrd_path}, copying to ${OS_PREFIX} location..."
        sudo cp "${initrd_path}" "${BOOT_SRC}/${OS_PREFIX}initrd.img" 2>/dev/null || true
        break
      fi
    done

    # Check if we found anything
    if [[ ! -f "${BOOT_SRC}/${OS_PREFIX}vmlinuz" || ! -f "${BOOT_SRC}/${OS_PREFIX}initrd.img" ]]; then
      echo "[!] No kernel/initrd found in image - this may cause boot failure"
      echo "[i] The system may still boot using the existing boot files"
    fi
  fi

  # Pi 5 DTB checks
  DTB_OK="no"
  for cand in \
      "${BOOT_SRC}/bcm2712-rpi-5-b.dtb" \
      "${BOOT_SRC}/${OS_PREFIX}bcm2712-rpi-5-b.dtb" \
      "${BOOT_SRC}/${OS_PREFIX}dtbs"/*/broadcom/bcm2712-rpi-5-b.dtb; do
    if ls "${cand}" >/dev/null 2>&1; then DTB_OK="yes"; break; fi
  done
  if [[ "$DTB_OK" != "yes" ]]; then
    echo "[!] bcm2712-rpi-5-b.dtb missing; fetching from Raspberry Pi firmware repo..."
    download_file "${FIRMWARE_BASE_URL}/bcm2712-rpi-5-b.dtb" \
      "${BOOT_SRC}/bcm2712-rpi-5-b.dtb" "Pi 5 DTB" || true
    sudo chown root:root "${BOOT_SRC}/bcm2712-rpi-5-b.dtb" 2>/dev/null || true
  fi

  # Ensure low-level blobs exist
  for fw in start4.elf fixup4.dat; do
    if [[ ! -f "${BOOT_SRC}/${fw}" ]]; then
      download_file "${FIRMWARE_BASE_URL}/${fw}" \
        "${BOOT_SRC}/${fw}" "firmware blob (${fw})" || true
      sudo chown root:root "${BOOT_SRC}/${fw}" 2>/dev/null || true
    fi
  done
else
  echo "[i] Legacy (pre-25.10) layout detected, verifying minimal boot files..."
  for f in start4.elf fixup4.dat bcm2712-rpi-5-b.dtb; do
    if [[ ! -f "${BOOT_SRC}/${f}" ]]; then
      download_file "${FIRMWARE_BASE_URL}/${f}" \
        "${BOOT_SRC}/${f}" "firmware blob (${f})" || true
      sudo chown root:root "${BOOT_SRC}/${f}" 2>/dev/null || true
    fi
  done
fi

# Color-safe output
if [[ -t 1 ]]; then
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

# Validation summary
echo "[i] Validation: summarizing boot partition..."
ls -lh "${BOOT_SRC}" | grep -E "vmlinuz|initrd|bcm2712|start4|fixup4|config|cmdline" || true

CRIT_OK=1
for f in "config.txt" "cmdline.txt" "start4.elf" "fixup4.dat"; do
  [[ -f "${BOOT_SRC}/$f" ]] || { echo "[!] MISSING: ${f}"; CRIT_OK=0; }
done

if [[ -n "${OS_PREFIX}" ]]; then
  for f in "${OS_PREFIX}vmlinuz" "${OS_PREFIX}initrd.img"; do
    [[ -f "${BOOT_SRC}/$f" ]] || { echo "[!] MISSING: ${f}"; CRIT_OK=0; }
  done
fi

echo "[i] PARTUUID map:"
sudo blkid | grep -E "$(basename "${NVME_DEVICE}")p[12]" || true

if [[ "${CRIT_OK}" -ne 1 ]]; then
  echo "${YELLOW}[!] Validation warnings above — boot may fail if critical files are missing.${RESET}"
else
  echo "${GREEN}[OK] Validation passed: required boot artifacts present.${RESET}"
fi

# EEPROM Configuration
echo "[i] Configuring EEPROM boot order..."

PI_MODEL=""
if [[ -f /proc/device-tree/model ]]; then
  PI_MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "")
fi

case "${PI_MODEL}" in
  *"Pi 5"*)
    BOOT_ORDER="0xf416"
    echo "[i] Detected Pi 5 - configuring NVMe boot priority"
    ;;
  *"Pi 4"*)
    BOOT_ORDER="0xf41"
    echo "[i] Detected Pi 4 - configuring USB boot priority (NVMe not supported)"
    ;;
  *)
    BOOT_ORDER="0xf41"
    echo "[i] Unknown Pi model - using default USB boot order"
    ;;
esac

if command -v rpi-eeprom-config >/dev/null 2>&1; then
  TMP=$(mktemp)
  sudo rpi-eeprom-config >"$TMP"
  if ! grep -q '^BOOT_ORDER=' "$TMP"; then
    echo "BOOT_ORDER=${BOOT_ORDER}" | sudo tee -a "$TMP" >/dev/null
  else
    sudo sed -i "s/^BOOT_ORDER=.*/BOOT_ORDER=${BOOT_ORDER}/" "$TMP"
  fi
  sudo rpi-eeprom-config --apply "$TMP"
  rm "$TMP"
  echo "[i] EEPROM boot order configured: ${BOOT_ORDER}"
else
  echo "[!] rpi-eeprom-config not found; install with: sudo apt install rpi-eeprom"
  echo "[i] Manual EEPROM configuration required:"
  echo "    sudo rpi-eeprom-config --edit"
  echo "    Add: BOOT_ORDER=${BOOT_ORDER}"
fi

# Post-flash validation summary
echo ""
echo "[i] Post-flash quick summary:"
echo "    → $(lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep nvme || true)"
echo "    → Mounted boot: $(mount | grep /mnt/boot || echo 'not mounted')"
echo ""

sudo umount /mnt/boot
sync

echo ""
echo "${GREEN}[OK] NVMe image prepared successfully.${RESET}"
echo ""
echo "Next steps:"
echo "  1. Power off the Pi: sudo poweroff"
echo "  2. Remove the SD card"
echo "  3. Power on the Pi (it will boot from NVMe)"
echo "  4. SSH in and verify with: lsblk"
echo "  5. Continue with the rest of the setup scripts"
echo ""
echo "On first boot, cloud-init config will apply (default user per your user-data)."
