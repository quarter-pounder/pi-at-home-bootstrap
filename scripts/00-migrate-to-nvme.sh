#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/utils.sh
load_env
detect_latest_lts
confirm_device

# --------------------------------------------------
# Constants
# --------------------------------------------------
readonly MIN_IMAGE_SIZE=500000000  # 500MB
readonly FIRMWARE_BASE_URL="https://raw.githubusercontent.com/raspberrypi/firmware/main/boot"
readonly UBUNTU_BASE_URL="https://cdimage.ubuntu.com/releases"
readonly BOOT_MNT="/mnt/boot"

# --------------------------------------------------
# Helpers
# --------------------------------------------------
download_file() {
  local url="$1"
  local output="$2"
  local description="$3"

  echo "[i] Downloading ${description}..."
  if ! wget -q -O "${output}" "${url}"; then
    echo "[!] Failed to download ${description} from ${url}"
    return 1
  fi

  if [[ ! -s "${output}" ]]; then
    echo "[!] Downloaded ${description} is empty"
    return 1
  fi

  echo "[OK] Successfully downloaded ${description}"
}

cleanup() {
  set +e
  echo "[i] Cleaning up..."
  mountpoint -q "${BOOT_MNT}" && sudo umount "${BOOT_MNT}" || true
  rm -f "${IMG_FILE}" "${IMG}" 2>/dev/null || true
}
trap cleanup EXIT

# --------------------------------------------------
# Environment Loading (.env + exports)
# --------------------------------------------------
if [[ -f ".env" ]]; then
  echo "[i] Loading .env configuration..."
  set -a
  source .env
  set +a
else
  echo "[!] .env file not found, using defaults where possible"
fi

# Sanity check for key vars
MISSING_ENV=()
for var in HOSTNAME USERNAME SSH_PUBLIC_KEY UBUNTU_VERSION NVME_DEVICE; do
  [[ -n "${!var:-}" ]] || MISSING_ENV+=("$var")
done
if (( ${#MISSING_ENV[@]} )); then
  echo "[!] Missing critical .env variables: ${MISSING_ENV[*]}"
  echo "    Please fix your .env before migration."
  exit 1
fi

# --------------------------------------------------
# Prepare image path and verify space
# --------------------------------------------------
IMG_FILE="ubuntu-${UBUNTU_VERSION}-preinstalled-server-arm64+raspi.img.xz"
IMG_URL="${UBUNTU_IMG_URL:-"${UBUNTU_BASE_URL}/${UBUNTU_VERSION}/release/${IMG_FILE}"}"
IMG="${IMG_FILE%.xz}"

AVAILABLE=$(($(df . | awk 'NR==2 {print $4}') * 1024))
REQUIRED=$((MIN_IMAGE_SIZE * 2))
if (( AVAILABLE < REQUIRED )); then
  echo "[!] Insufficient disk space: $((${AVAILABLE}/1024/1024))MB available, need $((${REQUIRED}/1024/1024))MB"
  exit 1
fi

# --------------------------------------------------
# Download and verify image
# --------------------------------------------------
echo "[i] Downloading Ubuntu ${UBUNTU_VERSION} image..."
echo "[i] URL: ${IMG_URL}"
curl -L --retry 5 --continue-at - -o "${IMG_FILE}" "${IMG_URL}"

if [[ ! -f "${IMG_FILE}" ]]; then
  echo "[!] Image not found after download"
  exit 1
fi

SIZE=$(stat -c%s "${IMG_FILE}")
echo "[i] Downloaded size: $((${SIZE}/1024/1024))MB"
if (( SIZE < MIN_IMAGE_SIZE )); then
  echo "[!] Image too small or truncated"
  exit 1
fi

# --------------------------------------------------
# Prevent flashing current root device
# --------------------------------------------------
if mount | grep -q "on / "; then
  ROOT_DEV=$(findmnt -no SOURCE /)
  if [[ "$ROOT_DEV" == *"${NVME_DEVICE}"* ]]; then
    echo "[!] Refusing to overwrite current root device ($ROOT_DEV)"
    exit 1
  fi
fi

# --------------------------------------------------
# Decompress image
# --------------------------------------------------
if [[ -f "${IMG}" ]]; then
  echo "[i] Reusing existing decompressed image"
else
  echo "[i] Decompressing image..."
  unxz -f "${IMG_FILE}"
fi

# --------------------------------------------------
# NVMe sanity check
# --------------------------------------------------
if [[ ! -b "${NVME_DEVICE}" ]]; then
  echo "[!] NVMe device not found: ${NVME_DEVICE}"
  exit 1
fi

if lsblk -no SIZE "${NVME_DEVICE}" | grep -q '^0B$'; then
  echo "[!] NVMe drive reports 0B size — reseat or power cycle"
  exit 1
fi

sudo umount "${NVME_DEVICE}"* 2>/dev/null || true
sudo blkdiscard "${NVME_DEVICE}" || true

# --------------------------------------------------
# Flash image
# --------------------------------------------------
echo "[i] Writing image to ${NVME_DEVICE}..."
if command -v pv >/dev/null; then
  pv "${IMG}" | sudo dd of="${NVME_DEVICE}" bs=4M conv=fsync
else
  sudo dd if="${IMG}" of="${NVME_DEVICE}" bs=4M status=progress conv=fsync
fi
sync

# --------------------------------------------------
# Mount boot partition
# --------------------------------------------------
sudo mkdir -p "${BOOT_MNT}"
sudo mount "${NVME_DEVICE}p1" "${BOOT_MNT}"

# --------------------------------------------------
# Cloud-init Injection
# --------------------------------------------------
echo "[i] Injecting cloud-init configuration..."
envsubst < cloudinit/user-data.template | sudo tee "${BOOT_MNT}/user-data" >/dev/null
envsubst < cloudinit/network-config.template | sudo tee "${BOOT_MNT}/network-config" >/dev/null
envsubst < cloudinit/meta-data.template | sudo tee "${BOOT_MNT}/meta-data" >/dev/null

# Keep a snapshot of environment
sudo cp .env "${BOOT_MNT}/.env.generated" 2>/dev/null || true

# --------------------------------------------------
# Firmware & Boot Verification (handles both legacy and os_prefix layouts)
# --------------------------------------------------
echo "[i] Verifying firmware and kernel files..."

OS_PREFIX=$(grep -Po '^(?i)os_prefix=\K.*' "${BOOT_MNT}/config.txt" 2>/dev/null | tail -1 || true)
if [[ -n "${OS_PREFIX}" ]]; then
  echo "[i] os_prefix detected: ${OS_PREFIX}"

  # Make sure the prefixed directory exists
  sudo mkdir -p "${BOOT_MNT}/${OS_PREFIX}"

  # Copy kernel/initrd from current/ if they exist but are missing in os_prefix
  if [[ -f "${BOOT_MNT}/current/vmlinuz" && ! -f "${BOOT_MNT}/${OS_PREFIX}vmlinuz" ]]; then
    echo "[i] Copying vmlinuz from current/..."
    sudo cp "${BOOT_MNT}/current/vmlinuz" "${BOOT_MNT}/${OS_PREFIX}vmlinuz"
  fi
  if [[ -f "${BOOT_MNT}/current/initrd.img" && ! -f "${BOOT_MNT}/${OS_PREFIX}initrd.img" ]]; then
    echo "[i] Copying initrd.img from current/..."
    sudo cp "${BOOT_MNT}/current/initrd.img" "${BOOT_MNT}/${OS_PREFIX}initrd.img"
  fi

  # Ensure DTB exists at root level for Pi 5
  if [[ ! -f "${BOOT_MNT}/bcm2712-rpi-5-b.dtb" ]]; then
    if [[ -f "${BOOT_MNT}/current/bcm2712-rpi-5-b.dtb" ]]; then
      echo "[i] Copying Pi 5 DTB from current/..."
      sudo cp "${BOOT_MNT}/current/bcm2712-rpi-5-b.dtb" "${BOOT_MNT}/bcm2712-rpi-5-b.dtb"
    else
      echo "[!] bcm2712-rpi-5-b.dtb missing; fetching from firmware repo..."
      download_file \
        "${FIRMWARE_BASE_URL}/bcm2712-rpi-5-b.dtb" \
        "${BOOT_MNT}/bcm2712-rpi-5-b.dtb" \
        "Pi 5 DTB" || true
    fi
  fi

  # Ensure low-level blobs exist (start4.elf / fixup4.dat)
  for fw in start4.elf fixup4.dat; do
    if [[ ! -f "${BOOT_MNT}/${fw}" ]]; then
      echo "[i] Downloading missing ${fw}..."
      download_file "${FIRMWARE_BASE_URL}/${fw}" "${BOOT_MNT}/${fw}" "${fw}" || true
    fi
  done

else
  echo "[i] Legacy layout detected — ensuring minimal boot blobs..."

  # Copy kernel/initrd from current/ if needed
  if [[ -f "${BOOT_MNT}/current/vmlinuz" && ! -f "${BOOT_MNT}/vmlinuz" ]]; then
    echo "[i] Copying vmlinuz from current/..."
    sudo cp "${BOOT_MNT}/current/vmlinuz" "${BOOT_MNT}/vmlinuz"
  fi
  if [[ -f "${BOOT_MNT}/current/initrd.img" && ! -f "${BOOT_MNT}/initrd.img" ]]; then
    echo "[i] Copying initrd.img from current/..."
    sudo cp "${BOOT_MNT}/current/initrd.img" "${BOOT_MNT}/initrd.img"
  fi

  # Ensure firmware blobs exist
  for f in start4.elf fixup4.dat bcm2712-rpi-5-b.dtb; do
    if [[ ! -f "${BOOT_MNT}/${f}" ]]; then
      echo "[i] Downloading missing ${f}..."
      download_file "${FIRMWARE_BASE_URL}/${f}" "${BOOT_MNT}/${f}" "${f}" || true
    fi
  done
fi

sudo chown -R root:root "${BOOT_MNT}" 2>/dev/null || true

# --------------------------------------------------
# EEPROM Configuration
# --------------------------------------------------
echo "[i] Checking and updating EEPROM boot order..."
if command -v rpi-eeprom-config >/dev/null 2>&1; then
  TMP=$(mktemp)
  sudo rpi-eeprom-config > "$TMP"
  if grep -q '^BOOT_ORDER=' "$TMP"; then
    sudo sed -i 's/^BOOT_ORDER=.*/BOOT_ORDER=0xf416/' "$TMP"
  else
    echo "BOOT_ORDER=0xf416" | sudo tee -a "$TMP" >/dev/null
  fi
  sudo rpi-eeprom-config --apply "$TMP"
  rm "$TMP"
  echo "[OK] EEPROM configured for NVMe-first boot (0xf416)"
else
  echo "[!] rpi-eeprom-config not available — configure manually if needed"
fi

# --------------------------------------------------
# Validation Summary
# --------------------------------------------------
echo "[i] Validation summary:"
ls -lh "${BOOT_MNT}" | grep -E "vmlinuz|initrd|bcm2712|start4|fixup4|config|cmdline" || true
echo ""
sudo blkid | grep -E "$(basename "${NVME_DEVICE}")p[12]" || true

sudo umount "${BOOT_MNT}"
sync

echo ""
echo "[OK] NVMe image prepared successfully!"
echo ""
echo "Next steps:"
echo "  1. Power off: sudo poweroff"
echo "  2. Remove the SD card"
echo "  3. Boot from NVMe"
echo "  4. SSH in and verify with: lsblk"
echo "  5. Continue setup after cloud-init completes"
