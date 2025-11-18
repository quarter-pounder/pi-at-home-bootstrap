#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

# Log
LOG_FILE="/var/log/nvme-migrate.log"
if ! mkdir -p /var/log 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
  LOG_FILE="$PWD/nvme-migrate.log"
fi
exec > >(tee -a "$LOG_FILE") 2>&1

source "$(dirname "$0")/utils.sh"

# Log fallback
if [[ "$LOG_FILE" != "/var/log/nvme-migrate.log" ]]; then
  log_warn "Cannot write to /var/log, using fallback: $LOG_FILE"
fi

log_info "NVMe Migration Script"
log_info "Migrates Raspberry Pi 5 from SD card to NVMe boot"

require_root

# --- dependency installation -----------------------------------------------

ensure_dependencies() {
  log_info "Checking for required dependencies..."

  local required_packages=()
  local optional_packages=()

  # Required packages
  if ! command -v curl >/dev/null 2>&1; then
    required_packages+=(curl)
  fi
  if ! command -v xz >/dev/null 2>&1 && ! command -v unxz >/dev/null 2>&1; then
    required_packages+=(xz-utils)
  fi
  if ! command -v parted >/dev/null 2>&1; then
    required_packages+=(parted)
  fi
  if ! command -v fdisk >/dev/null 2>&1; then
    required_packages+=(util-linux)
  fi
  if ! command -v mkfs.vfat >/dev/null 2>&1; then
    required_packages+=(dosfstools)
  fi
  if ! command -v mkfs.ext4 >/dev/null 2>&1; then
    required_packages+=(e2fsprogs)
  fi

  # Optional packages (install if available)
  if ! command -v pv >/dev/null 2>&1; then
    optional_packages+=(pv)
  fi
  if ! command -v rpi-eeprom-config >/dev/null 2>&1; then
    optional_packages+=(rpi-eeprom)
  fi

  if (( ${#required_packages[@]} > 0 )); then
    log_info "Installing required packages: ${required_packages[*]}"
    apt-get update -qq
    apt-get install -y "${required_packages[@]}" || {
      log_error "Failed to install required packages"
      exit 1
    }
    log_success "Required packages installed"
  else
    log_success "All required dependencies are present"
  fi

  if (( ${#optional_packages[@]} > 0 )); then
    log_info "Attempting to install optional packages: ${optional_packages[*]}"
    if apt-get install -y "${optional_packages[@]}" 2>/dev/null; then
      log_success "Optional packages installed"
    else
      log_warn "Some optional packages could not be installed (will continue anyway)"
    fi
  fi
}

ensure_dependencies

# Constants
readonly MIN_IMAGE_SIZE=500000000  # 500MB
readonly FIRMWARE_BASE_URL="https://raw.githubusercontent.com/raspberrypi/firmware/main/boot"
readonly UBUNTU_BASE_URL="https://cdimage.ubuntu.com/releases"
readonly BOOT_MNT="/mnt/boot"

# Detect latest Ubuntu LTS version
detect_latest_lts() {
  if [[ -z "${UBUNTU_VERSION:-}" ]]; then
    log_debug "Auto-detecting Ubuntu LTS version..."
    local detected
    detected=$(curl -s https://api.launchpad.net/devel/ubuntu/series 2>/dev/null \
      | grep -oP '"name": "\K[0-9]{2}\.[0-9]{2}(?=")' \
      | sort -V | tail -1 || echo "24.04")
    if [[ "$detected" == "24.04" ]]; then
      log_warn "Could not detect Ubuntu version, defaulting to 24.04"
    fi
    UBUNTU_VERSION="$detected"
    log_info "Auto-detected Ubuntu LTS: $UBUNTU_VERSION"
    log_debug "Detected UBUNTU_VERSION=$UBUNTU_VERSION"
  else
    log_info "Using Ubuntu version: $UBUNTU_VERSION"
    log_debug "Using provided UBUNTU_VERSION=$UBUNTU_VERSION"
  fi
}

# Confirm NVMe device
confirm_device() {
  if [[ -z "${NVME_DEVICE:-}" ]]; then
    log_debug "Auto-detecting NVMe device..."
    NVME_DEVICE=$(lsblk -dno NAME,TYPE | grep disk | grep nvme | awk '{print "/dev/"$1}' | head -1)
    log_debug "Auto-detected NVME_DEVICE=$NVME_DEVICE"
  else
    log_debug "Using provided NVME_DEVICE=$NVME_DEVICE"
  fi

  if [[ -z "${NVME_DEVICE}" ]]; then
    log_error "No NVMe device detected. Check connection."
    log_info "Available block devices:"
    lsblk -dno NAME,TYPE,SIZE | grep disk
    exit 1
  fi

  if [[ ! -b "$NVME_DEVICE" ]]; then
    log_error "NVMe device not found: $NVME_DEVICE"
    exit 1
  fi

  if lsblk -no SIZE "$NVME_DEVICE" | grep -q '^0B$'; then
    log_error "NVMe drive reports 0B size — reseat or power cycle"
    exit 1
  fi

  local size; size=$(lsblk -no SIZE "$NVME_DEVICE")
  log_info "NVMe device: $NVME_DEVICE ($size)"
  log_debug "NVMe device confirmed: $NVME_DEVICE, size=$size"

  confirm_continue "Proceed with migration to $NVME_DEVICE? (yes/no): "
}

# Download helper
download_file() {
  local url="$1"
  local output="$2"
  local description="$3"

  log_info "Downloading ${description}..."
  if ! wget -q -O "${output}" "${url}"; then
    log_error "Failed to download ${description} from ${url}"
    return 1
  fi

  if [[ ! -s "${output}" ]]; then
    log_error "Downloaded ${description} is empty"
    return 1
  fi

  log_success "Successfully downloaded ${description}"
}

# Cleanup on exit
cleanup() {
  set +e
  log_info "Cleaning up..."
  mountpoint -q "${BOOT_MNT}" && umount "${BOOT_MNT}" || true
  [[ -n "${IMG_FILE:-}" ]] && rm -f "${IMG_FILE}" "${IMG_FILE}.SHA256SUMS" 2>/dev/null || true
  [[ -n "${IMG:-}" ]] && rm -f "${IMG}" 2>/dev/null || true
}
trap cleanup EXIT

# Load environment if available
if [[ -f config-registry/env/base.env ]]; then
  log_info "Loading environment from config-registry/env/base.env"
  set -a
  source config-registry/env/base.env
  set +a
fi

# Detect and confirm
detect_latest_lts
confirm_device

# Prevent flashing current root device
ROOT_DEV=""
if mount | grep -q "on / "; then
  ROOT_DEV=$(findmnt -no SOURCE /)
  log_debug "Detected ROOT_DEV=$ROOT_DEV, NVME_DEVICE=$NVME_DEVICE"
  if [[ "$ROOT_DEV" == *"${NVME_DEVICE}"* ]]; then
    log_error "Refusing to overwrite current root device ($ROOT_DEV)"
    log_error "This script is for migrating FROM SD card TO NVMe"
    exit 1
  fi
else
  log_debug "Could not determine root device"
fi
log_debug "Root device check passed: ROOT_DEV=$ROOT_DEV, NVME_DEVICE=$NVME_DEVICE"

# Prepare image
# Detect actual image filename (may include patch version like 24.04.3)
detect_image_filename() {
  if [[ -n "${UBUNTU_IMG_URL:-}" ]]; then
    # Use provided URL directly
    IMG_FILE=$(basename "${UBUNTU_IMG_URL}")
    IMG_URL="${UBUNTU_IMG_URL}"
  else
    # Try to find the actual filename in the release directory
    local release_url="${UBUNTU_BASE_URL}/${UBUNTU_VERSION}/release/"
    log_debug "Checking available images at ${release_url}"
    local filename
    filename=$(curl -s "${release_url}" 2>/dev/null \
      | grep -i "preinstalled-server-arm64.*raspi.*img.xz" \
      | sed -n 's/.*href="\(ubuntu-'${UBUNTU_VERSION}'[^"]*preinstalled-server-arm64+raspi\.img\.xz\)".*/\1/p' \
      | head -1)

    if [[ -n "$filename" ]]; then
      IMG_FILE="$filename"
      IMG_URL="${release_url}${IMG_FILE}"
      log_debug "Found image: ${IMG_FILE}"
    else
      # Fallback to expected filename
      IMG_FILE="ubuntu-${UBUNTU_VERSION}-preinstalled-server-arm64+raspi.img.xz"
      IMG_URL="${release_url}${IMG_FILE}"
      log_warn "Could not detect exact image filename, using: ${IMG_FILE}"
    fi
  fi
  IMG="${IMG_FILE%.xz}"
}

detect_image_filename

AVAILABLE=$(($(df . | awk 'NR==2 {print $4}') * 1024))
REQUIRED=$((MIN_IMAGE_SIZE * 2))
if (( AVAILABLE < REQUIRED )); then
  log_error "Insufficient disk space: $((${AVAILABLE}/1024/1024))MB available, need $((${REQUIRED}/1024/1024))MB"
  exit 1
fi

# Download checksums file
SHA256SUM_URL="${UBUNTU_BASE_URL}/${UBUNTU_VERSION}/release/SHA256SUMS"
SHA256SUM_FILE="${IMG_FILE}.SHA256SUMS"
log_info "Fetching SHA256 checksums..."
if ! curl -L --fail --retry 3 -s -o "$SHA256SUM_FILE" "$SHA256SUM_URL"; then
  log_warn "Failed to download checksums file, verification may be skipped"
  SHA256SUM_FILE=""
fi

# SHA256 verification helper
verify_sha256() {
  local file=$1
  local expected_hash=$2
  if [[ -z "$expected_hash" ]]; then
    log_warn "No checksum provided, skipping verification"
    return 0
  fi
  log_info "Verifying SHA256 checksum..."
  local actual_hash
  actual_hash=$(sha256sum "$file" | cut -d' ' -f1)
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

# Download image
if [[ -f "${IMG}" ]]; then
  log_info "Reusing existing decompressed image: ${IMG}"
  log_info "Note: SHA256 verification skipped for decompressed image (verify .xz file instead)"
elif [[ -f "${IMG_FILE}" ]]; then
  log_info "Reusing existing compressed image: ${IMG_FILE}"
  # Verify existing compressed image
  if [[ -f "$SHA256SUM_FILE" ]]; then
    EXPECTED_HASH=$(grep " ${IMG_FILE}$" "$SHA256SUM_FILE" | cut -d' ' -f1)
    if [[ -n "$EXPECTED_HASH" ]]; then
      verify_sha256 "$IMG_FILE" "$EXPECTED_HASH" || {
        log_error "Existing compressed image failed verification"
        exit 1
      }
    else
      log_warn "Checksum for ${IMG_FILE} not found in SHA256SUMS"
    fi
  fi
else
  log_info "Downloading Ubuntu ${UBUNTU_VERSION} image..."
  log_info "URL: ${IMG_URL}"
  curl -L --retry-delay 10 --continue-at - -o "${IMG_FILE}" "${IMG_URL}" || {
    log_error "Failed to download image"
    exit 1
  }

  if [[ ! -f "${IMG_FILE}" ]]; then
    log_error "Image not found after download"
    exit 1
  fi

  SIZE=$(stat -c%s "${IMG_FILE}")
  log_info "Downloaded size: $((${SIZE}/1024/1024))MB"
  if (( SIZE < MIN_IMAGE_SIZE )); then
    log_error "Image too small or truncated"
    exit 1
  fi

  # Verify downloaded compressed image
  if [[ -n "${SHA256SUM_FILE:-}" ]] && [[ -f "$SHA256SUM_FILE" ]]; then
    EXPECTED_HASH=$(grep " ${IMG_FILE}$" "$SHA256SUM_FILE" | cut -d' ' -f1)
    if [[ -n "$EXPECTED_HASH" ]]; then
      verify_sha256 "$IMG_FILE" "$EXPECTED_HASH" || {
        log_error "Downloaded image failed verification"
        rm -f "$IMG_FILE"
        exit 1
      }
    else
      log_warn "Checksum for ${IMG_FILE} not found in SHA256SUMS - file may be invalid"
    fi
  else
    log_warn "SHA256SUMS file not available, skipping verification"
  fi
fi

# Decompress if needed
if [[ ! -f "${IMG}" ]]; then
  log_info "Decompressing image..."
  if ! unxz -f "${IMG_FILE}"; then
    log_error "Failed to decompress image: ${IMG_FILE}"
    exit 1
  fi
fi

# Verify decompressed image
if [[ ! -f "${IMG}" ]]; then
  log_error "Decompressed image not found: ${IMG}"
  exit 1
fi

IMG_SIZE=$(stat -c%s "${IMG}")
log_info "Image size: $((${IMG_SIZE}/1024/1024/1024))GB"

# Unmount NVMe partitions
log_info "Unmounting existing partitions on ${NVME_DEVICE}..."
for part in "${NVME_DEVICE}"p* "${NVME_DEVICE}"[0-9]*; do
  [[ -e "$part" ]] && mountpoint -q "$part" 2>/dev/null && umount "$part" 2>/dev/null || true
done

# Secure erase (optional but recommended)
log_info "Erasing NVMe device (this may take a moment)..."
blkdiscard -f "${NVME_DEVICE}" 2>/dev/null || log_warn "blkdiscard failed, continuing anyway"

# Flash image
log_info "Writing image to ${NVME_DEVICE}..."
log_warn "This will destroy all data on ${NVME_DEVICE}"
log_warn "DO NOT interrupt this process!"
confirm_continue "Proceed with writing image to ${NVME_DEVICE}? This is DESTRUCTIVE! (yes/no): "

if command -v pv >/dev/null 2>&1; then
  pv "${IMG}" | dd of="${NVME_DEVICE}" bs=4M conv=fsync
else
  dd if="${IMG}" of="${NVME_DEVICE}" bs=4M status=progress conv=fsync
fi

sync
log_success "Image written successfully"

# Refresh partition table
log_info "Refreshing partition table..."
partprobe "${NVME_DEVICE}" || partx -u "${NVME_DEVICE}" || true
sleep 3

# Mount boot partition
mkdir -p "${BOOT_MNT}"
mount "${NVME_DEVICE}p1" "${BOOT_MNT}"

# Cloud-init configuration (optional)
if [[ -f legacy/cloudinit/user-data.template ]]; then
  log_info "Injecting cloud-init configuration..."

  # Load environment variables for substitution
  if [[ -f config-registry/env/base.env ]]; then
    set -a
    source config-registry/env/base.env
    set +a
  fi

  # Set CFG_ variables with fallbacks
  export CFG_HOSTNAME="${HOSTNAME:-pi-forge}"
  export CFG_USERNAME="${USERNAME:-pi}"
  export CFG_SSH_KEY="${SSH_PUBLIC_KEY:-}"
  export CFG_TIMEZONE="${TIMEZONE:-UTC}"
  export CFG_LOCALE="${LOCALE:-en_US.UTF-8}"

  envsubst '$CFG_HOSTNAME $CFG_USERNAME $CFG_SSH_KEY $CFG_TIMEZONE $CFG_LOCALE' \
    < legacy/cloudinit/user-data.template > "${BOOT_MNT}/user-data"
  envsubst '$CFG_HOSTNAME $CFG_USERNAME $CFG_SSH_KEY $CFG_TIMEZONE $CFG_LOCALE' \
    < legacy/cloudinit/network-config.template > "${BOOT_MNT}/network-config"
  envsubst '$CFG_HOSTNAME $CFG_USERNAME $CFG_SSH_KEY $CFG_TIMEZONE $CFG_LOCALE' \
    < legacy/cloudinit/meta-data.template > "${BOOT_MNT}/meta-data"

  log_success "Cloud-init configuration injected"
else
  log_warn "Cloud-init templates not found at legacy/cloudinit/ (optional)"
fi

# Firmware verification and setup
log_info "Verifying firmware and boot files..."

OS_PREFIX=$(grep -Po '^(?i)os_prefix=\K.*' "${BOOT_MNT}/config.txt" 2>/dev/null | tail -1 || true)

if [[ -n "${OS_PREFIX}" ]]; then
  log_info "os_prefix detected: ${OS_PREFIX}"

  mkdir -p "${BOOT_MNT}/${OS_PREFIX}"

  # Copy kernel and initrd if needed
  if [[ -f "${BOOT_MNT}/current/vmlinuz" && ! -f "${BOOT_MNT}/${OS_PREFIX}vmlinuz" ]]; then
    log_info "Copying vmlinuz from current/..."
    cp "${BOOT_MNT}/current/vmlinuz" "${BOOT_MNT}/${OS_PREFIX}vmlinuz"
  fi
  if [[ -f "${BOOT_MNT}/current/initrd.img" && ! -f "${BOOT_MNT}/${OS_PREFIX}initrd.img" ]]; then
    log_info "Copying initrd.img from current/..."
    cp "${BOOT_MNT}/current/initrd.img" "${BOOT_MNT}/${OS_PREFIX}initrd.img"
  fi

  # Ensure Pi 5 DTB exists
  if [[ ! -f "${BOOT_MNT}/bcm2712-rpi-5-b.dtb" ]]; then
    if [[ -f "${BOOT_MNT}/current/bcm2712-rpi-5-b.dtb" ]]; then
      log_info "Copying Pi 5 DTB from current/..."
      cp "${BOOT_MNT}/current/bcm2712-rpi-5-b.dtb" "${BOOT_MNT}/bcm2712-rpi-5-b.dtb"
    else
      log_info "Downloading Pi 5 DTB from firmware repo..."
      download_file "${FIRMWARE_BASE_URL}/bcm2712-rpi-5-b.dtb" "${BOOT_MNT}/bcm2712-rpi-5-b.dtb" "Pi 5 DTB" || true
    fi
  fi

  # Ensure firmware files exist
  for fw in start4.elf fixup4.dat; do
    if [[ ! -f "${BOOT_MNT}/${fw}" ]]; then
      log_info "Downloading missing ${fw}..."
      download_file "${FIRMWARE_BASE_URL}/${fw}" "${BOOT_MNT}/${fw}" "${fw}" || true
    fi
  done
else
  log_info "Legacy layout detected — ensuring minimal boot files..."

  # Copy kernel and initrd if needed
  if [[ -f "${BOOT_MNT}/current/vmlinuz" && ! -f "${BOOT_MNT}/vmlinuz" ]]; then
    log_info "Copying vmlinuz from current/..."
    cp "${BOOT_MNT}/current/vmlinuz" "${BOOT_MNT}/vmlinuz"
  fi
  if [[ -f "${BOOT_MNT}/current/initrd.img" && ! -f "${BOOT_MNT}/initrd.img" ]]; then
    log_info "Copying initrd.img from current/..."
    cp "${BOOT_MNT}/current/initrd.img" "${BOOT_MNT}/initrd.img"
  fi

  # Ensure firmware files exist
  for f in start4.elf fixup4.dat bcm2712-rpi-5-b.dtb; do
    if [[ ! -f "${BOOT_MNT}/${f}" ]]; then
      log_info "Downloading missing ${f}..."
      download_file "${FIRMWARE_BASE_URL}/${f}" "${BOOT_MNT}/${f}" "${f}" || true
    fi
  done
fi

chown -R root:root "${BOOT_MNT}" 2>/dev/null || true

# EEPROM configuration
log_info "Checking and updating EEPROM boot order..."
if command -v rpi-eeprom-config >/dev/null 2>&1; then
  TMP=$(mktemp)
  rpi-eeprom-config > "$TMP"
  if grep -q '^BOOT_ORDER=' "$TMP"; then
    sed -i 's/^BOOT_ORDER=.*/BOOT_ORDER=0xf416/' "$TMP"
  else
    echo "BOOT_ORDER=0xf416" >> "$TMP"
  fi
  rpi-eeprom-config --apply "$TMP"
  rm "$TMP"
  log_success "EEPROM configured for NVMe-first boot (0xf416)"
else
  log_warn "rpi-eeprom-config not available — configure manually if needed"
  log_info "Set BOOT_ORDER=0xf416 using: sudo rpi-eeprom-config --edit"
fi

# Validation summary
log_info "Validation summary:"
ls -lh "${BOOT_MNT}" | grep -E "vmlinuz|initrd|bcm2712|start4|fixup4|config|cmdline" || true
echo ""
blkid | grep -E "$(basename "${NVME_DEVICE}")p[12]" || true

umount "${BOOT_MNT}"
sync

echo ""
log_success "NVMe image prepared successfully!"
echo ""
echo "Next steps:"
echo "  1. Power off: sudo poweroff"
echo "  2. Remove the SD card"
echo "  3. Boot from NVMe"
echo "  4. SSH in and verify with: lsblk"
echo "  5. Continue setup after cloud-init completes"
echo ""
