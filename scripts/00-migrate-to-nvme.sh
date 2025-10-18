#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "[!] .env file not found. Please copy env.example to .env and configure it."
  exit 1
fi

source .env

detect_nvme() {
  NVME_DEVICE=$(lsblk -dno NAME,TYPE | grep disk | grep nvme | awk '{print "/dev/"$1}' | head -1)
  if [[ -z "$NVME_DEVICE" ]]; then
    echo "[!] No NVMe device found. Is it connected?"
    exit 1
  fi
  echo "[i] Detected NVMe device: ${NVME_DEVICE}"
}

detect_nvme

echo "[!] WARNING: This will erase all data on ${NVME_DEVICE}"
echo "[!] Current system will be migrated from SD card to NVMe"
echo "[!] The system will reboot after migration"
echo ""
lsblk
echo ""
read -p "Continue? Type 'yes' to proceed: " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
  echo "Migration cancelled"
  exit 0
fi

echo "[i] Installing required tools..."
sudo apt update
sudo apt install -y rsync parted rpi-eeprom

echo "[i] Unmounting NVMe if mounted..."
sudo umount ${NVME_DEVICE}* 2>/dev/null || true

echo "[i] Checking NVMe drive status..."
if ! lsblk ${NVME_DEVICE} >/dev/null 2>&1; then
  echo "[!] Error: NVMe drive not accessible at ${NVME_DEVICE}"
  echo "[i] Available NVMe devices:"
  lsblk | grep nvme || echo "No NVMe devices found"
  exit 1
fi

echo "[i] Checking drive health before wipe..."
sudo nvme smart-log ${NVME_DEVICE} 2>/dev/null || echo "[!] Warning: Could not read SMART data"

echo "[i] Running additional diagnostics..."
echo "[i] Drive information:"
DRIVE_INFO=$(sudo nvme id-ctrl ${NVME_DEVICE} 2>/dev/null || echo "Cannot read controller info")
echo "$DRIVE_INFO"

echo "[i] Checking power supply status:"
vcgencmd get_throttled 2>/dev/null || echo "[!] Cannot check power status"

echo "[i] Drive temperature:"
sudo nvme get-feature -f 0x02 -n 1 ${NVME_DEVICE} 2>/dev/null || echo "[!] Cannot read temperature"

echo "[i] Testing basic read/write capability..."
if ! sudo dd if=${NVME_DEVICE} of=/dev/null bs=1M count=1 2>/dev/null; then
  echo "[!] Error: Cannot read from drive - this indicates a serious hardware issue"
  echo ""
  echo "[i] CRITICAL ISSUE DETECTED:"
  echo "    - Drive shows 0B size (should show ~256GB)"
  echo "    - Cannot read controller information"
  echo "    - Cannot read SMART data"
  echo "    - Cannot perform basic I/O operations"
  echo ""
  echo "[i] This is NOT a software issue - it's a hardware problem:"
  echo "    - Drive is not properly seated in M.2 slot"
  echo "    - Drive is defective or damaged"
  echo "    - M.2 slot is damaged"
  echo "    - Power supply cannot provide enough current"
  echo ""
  echo "[i] IMMEDIATE TROUBLESHOOTING STEPS:"
  echo "    1. POWER OFF the Pi completely"
  echo "    2. Remove the NVMe drive from M.2 slot"
  echo "    3. Check for physical damage:"
  echo "       - Bent pins on the drive"
  echo "       - Scratches or dents"
  echo "       - Missing components"
  echo "    4. Re-seat the drive firmly in the M.2 slot"
  echo "    5. Power on and test again"
  echo ""
  echo "[i] If the problem persists:"
  echo "    - Try a different NVMe drive (Samsung, WD, Crucial)"
  echo "    - Test the drive in another system"
  echo "    - Check if M.2 slot works with another drive"
  echo "    - Consider RMA if drive is defective"
  echo ""
  echo "[i] For now, continuing with SD card setup..."
  echo "    Run: ./scripts/00-optimize-sd-card.sh"
  exit 1
fi

echo "[i] Wiping NVMe device..."
if ! sudo wipefs -a ${NVME_DEVICE}; then
  echo "[!] Error: Failed to wipe NVMe device"
  echo "[i] This indicates a serious drive issue. Possible causes:"
  echo "    - Drive is failing or corrupted"
  echo "    - Drive is not compatible with Pi 5"
  echo "    - Power supply is inadequate (Pi 5 needs 5V/3A minimum)"
  echo "    - Drive is not properly seated in M.2 slot"
  echo ""
  echo "[i] Trying alternative wipe method..."
  if ! sudo dd if=/dev/zero of=${NVME_DEVICE} bs=1M count=100 2>/dev/null; then
    echo "[!] Error: Alternative wipe method also failed"
    echo "[i] This drive appears to be unusable. Please check:"
    echo "    1. Drive is properly seated in M.2 slot"
    echo "    2. Power supply provides adequate current (5V/3A minimum)"
    echo "    3. Try a different NVMe drive"
    echo "    4. Check if drive works in another system"
    exit 1
  fi
  echo "[i] Alternative wipe method succeeded"
fi

echo "[i] Discarding unused blocks..."
sudo blkdiscard ${NVME_DEVICE} 2>/dev/null || echo "[!] Warning: blkdiscard failed (this is often normal)"

echo "[i] Creating partition table..."
echo "[i] Checking NVMe drive health..."
sudo nvme smart-log ${NVME_DEVICE} 2>/dev/null || echo "[!] Warning: Could not read NVMe SMART data"

echo "[i] Creating GPT partition table..."
if ! sudo parted -s ${NVME_DEVICE} mklabel gpt; then
  echo "[!] Error: Failed to create GPT partition table"
  echo "[i] This might indicate a drive issue. Check:"
  echo "    - NVMe drive is properly seated"
  echo "    - Power supply is adequate (Pi 5 needs 5V/3A minimum)"
  echo "    - Drive is compatible with Pi 5"
  echo ""
  echo "[i] Alternative: You can continue with high quality SD card"
  echo "    - SD cards have limited write cycles"
  echo "    - Consider using tmpfs for logs and temp files"
  echo "    - Enable swap on SD card for better performance"
  echo "    - Plan to migrate to NVMe when possible"
  exit 1
fi

echo "[i] Creating boot partition (512MB)..."
if ! sudo parted -s ${NVME_DEVICE} mkpart primary fat32 0% 512MB; then
  echo "[!] Error: Failed to create boot partition"
  exit 1
fi

echo "[i] Creating root partition (remaining space)..."
if ! sudo parted -s ${NVME_DEVICE} mkpart primary ext4 512MB 100%; then
  echo "[!] Error: Failed to create root partition"
  exit 1
fi

echo "[i] Setting boot flag..."
if ! sudo parted -s ${NVME_DEVICE} set 1 boot on; then
  echo "[!] Error: Failed to set boot flag"
  exit 1
fi

sleep 2
echo "[i] Refreshing partition table..."
sudo partprobe ${NVME_DEVICE}
sleep 2

# Verify partitions were created
echo "[i] Verifying partitions..."
if ! lsblk ${NVME_DEVICE} | grep -q "p1\|p2"; then
  echo "[!] Error: Partitions not detected after creation"
  echo "[i] Trying alternative partitioning method..."

  # Try using fdisk as fallback
  echo "[i] Using fdisk as fallback..."
  sudo fdisk ${NVME_DEVICE} <<EOF
g
n
1

+512M
t
1
c
n
2


w
EOF

  sleep 2
  sudo partprobe ${NVME_DEVICE}
  sleep 2
fi

BOOT_PART="${NVME_DEVICE}p1"
ROOT_PART="${NVME_DEVICE}p2"

# Final verification
if [[ ! -b ${BOOT_PART} ]] || [[ ! -b ${ROOT_PART} ]]; then
  echo "[!] Error: Required partitions not found"
  echo "[i] Available partitions:"
  lsblk ${NVME_DEVICE}
  exit 1
fi

echo "[i] Partitions created successfully:"
lsblk ${NVME_DEVICE}

echo "[i] Formatting partitions..."
sudo mkfs.vfat -F 32 -n BOOT ${BOOT_PART}
sudo mkfs.ext4 -F -L writable ${ROOT_PART}

echo "[i] Mounting NVMe partitions..."
sudo mkdir -p /mnt/nvme-boot
sudo mkdir -p /mnt/nvme-root
sudo mount ${BOOT_PART} /mnt/nvme-boot
sudo mount ${ROOT_PART} /mnt/nvme-root

# Verify mounts
if ! mountpoint -q /mnt/nvme-boot; then
  echo "[!] Error: Boot partition not mounted properly"
  exit 1
fi
if ! mountpoint -q /mnt/nvme-root; then
  echo "[!] Error: Root partition not mounted properly"
  exit 1
fi
echo "[i] Partitions mounted successfully"

echo "[i] Copying boot partition..."
# Detect if /boot/firmware exists (Ubuntu) or just /boot (Raspberry Pi OS)
if [[ -d /boot/firmware && -n "$(ls -A /boot/firmware 2>/dev/null)" ]]; then
  echo "[i] Detected Ubuntu-style boot layout (/boot/firmware)"
  BOOT_SRC="/boot/firmware"
else
  echo "[i] Detected Raspberry Pi OS-style boot layout (/boot)"
  BOOT_SRC="/boot"
fi

echo "[i] Copying boot files from ${BOOT_SRC}..."
sudo rsync -axHAWX --info=progress2 ${BOOT_SRC}/ /mnt/nvme-boot/

echo "[i] Copying root filesystem (this may take several minutes)..."
sudo rsync -axHAWX --info=progress2 \
  --exclude /mnt/nvme-root \
  --exclude /mnt/nvme-boot \
  --exclude /proc \
  --exclude /sys \
  --exclude /dev \
  --exclude /tmp \
  / /mnt/nvme-root/

echo "[i] Creating system directories on NVMe..."
sudo mkdir -p /mnt/nvme-root/{proc,sys,dev,tmp}

echo "[i] Getting partition UUIDs..."
BOOT_UUID=$(sudo blkid -s PARTUUID -o value ${BOOT_PART})
ROOT_UUID=$(sudo blkid -s PARTUUID -o value ${ROOT_PART})

echo "[i] Updating fstab on NVMe..."
sudo tee /mnt/nvme-root/etc/fstab >/dev/null <<EOF
PARTUUID=${ROOT_UUID}  /               ext4   defaults,noatime  0 1
PARTUUID=${BOOT_UUID}  /boot/firmware  vfat   defaults          0 2
EOF

echo "[i] Updating boot configuration..."

# --- Kernel and initrd handling ---
echo "[i] Searching for kernel and initrd images..."
KERNEL_IMG=$(ls ${BOOT_SRC}/vmlinuz* 2>/dev/null | sort -V | tail -1 || true)
INITRD_IMG=$(ls ${BOOT_SRC}/initrd.img* 2>/dev/null | sort -V | tail -1 || true)

if [[ -f "$KERNEL_IMG" ]]; then
  echo "[i] Copying kernel image to NVMe as kernel_2712.img"
  sudo cp "$KERNEL_IMG" /mnt/nvme-boot/kernel_2712.img
else
  echo "[!] Warning: No kernel image found in ${BOOT_SRC}"
fi

if [[ -f "$INITRD_IMG" ]]; then
  echo "[i] Copying initrd image to NVMe"
  sudo cp "$INITRD_IMG" /mnt/nvme-boot/initrd.img
else
  echo "[!] Warning: No initrd image found in ${BOOT_SRC}"
fi

# --- Device tree and overlays ---
echo "[i] Ensuring device tree and overlays are present..."
sudo mkdir -p /mnt/nvme-boot/overlays
if compgen -G "${BOOT_SRC}/bcm2712*" > /dev/null; then
  sudo cp ${BOOT_SRC}/bcm2712* /mnt/nvme-boot/ 2>/dev/null || true
fi
sudo cp -r ${BOOT_SRC}/overlays/* /mnt/nvme-boot/overlays/ 2>/dev/null || true

# --- cmdline.txt ---
echo "[i] Updating cmdline.txt..."
if [[ -f /mnt/nvme-boot/cmdline.txt ]]; then
  sudo sed -i "s/root=[^ ]*/root=PARTUUID=${ROOT_UUID}/" /mnt/nvme-boot/cmdline.txt
  echo "[i] Updated cmdline.txt with new root UUID"
else
  echo "console=serial0,115200 console=tty1 root=PARTUUID=${ROOT_UUID} rootfstype=ext4 fsck.repair=yes rootwait quiet splash" \
    | sudo tee /mnt/nvme-boot/cmdline.txt >/dev/null
  echo "[i] Created default cmdline.txt"
fi

# --- config.txt ---
echo "[i] Creating config.txt for Pi 5 NVMe boot..."
sudo tee /mnt/nvme-boot/config.txt >/dev/null <<EOF
[all]
arm_64bit=1
kernel=kernel_2712.img
initramfs initrd.img followkernel
device_tree=bcm2712-rpi-5-b.dtb
dtoverlay=disable-bt
enable_uart=1
gpu_mem=16
boot_order=0xf416
EOF

# --- usercfg.txt ---
echo "[i] Creating usercfg.txt for Pi 5..."
sudo tee /mnt/nvme-boot/usercfg.txt >/dev/null <<EOF
# Additional user configuration
program_usb_boot_mode=1
program_usb_boot_timeout=1
EOF

# --- EEPROM Configuration ---
echo "[i] Configuring EEPROM boot order for Pi 5..."
if command -v rpi-eeprom-config >/dev/null 2>&1; then
  echo "[i] Setting boot order to 0xf416 (NVMe first, then SD card)..."
  if ! sudo rpi-eeprom-config --edit <<EOF
BOOT_ORDER=0xf416
EOF
  then
    echo "[!] Warning: Failed to set EEPROM boot order"
    echo "[i] You may need to set this manually:"
    echo "    sudo rpi-eeprom-config --edit"
    echo "    Add: BOOT_ORDER=0xf416"
  else
    echo "[i] EEPROM boot order configured successfully"
  fi
else
  echo "[!] Warning: rpi-eeprom-config not found"
  echo "[i] Install it with: sudo apt install rpi-eeprom"
  echo "[i] Then run: sudo rpi-eeprom-config --edit"
  echo "[i] Add: BOOT_ORDER=0xf416"
fi

# --- Verify critical files ---
echo "[i] Verifying critical boot files..."
MISSING_FILES=()
for file in "kernel_2712.img" "bcm2712-rpi-5-b.dtb" "armstub8-2712.bin" "start4.elf" "fixup4.dat"; do
  if [[ ! -f "/mnt/nvme-boot/$file" ]]; then
    MISSING_FILES+=("$file")
  fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
  echo "[!] Warning: Missing critical boot files:"
  for file in "${MISSING_FILES[@]}"; do
    echo "    - $file"
  done
  echo "[i] Attempting to recover missing firmware files..."
  sudo cp ${BOOT_SRC}/armstub8-2712.bin /mnt/nvme-boot/ 2>/dev/null || true
  sudo cp ${BOOT_SRC}/start4.elf /mnt/nvme-boot/ 2>/dev/null || true
  sudo cp ${BOOT_SRC}/fixup4.dat /mnt/nvme-boot/ 2>/dev/null || true
else
  echo "[i] All critical boot files present"
fi

echo "[i] Final verification of NVMe boot partition..."
ls -la /mnt/nvme-boot/ | head -20

echo "[i] Critical files check:"
for file in "kernel_2712.img" "bcm2712-rpi-5-b.dtb" "armstub8-2712.bin" "start4.elf" "fixup4.dat" "config.txt" "cmdline.txt"; do
  if [[ -f "/mnt/nvme-boot/$file" ]]; then
    echo " [OK] $file exists"
  else
    echo " [MISSING] $file"
  fi
done

echo "[i] Syncing filesystems..."
sync

echo "[i] Unmounting NVMe..."
sudo umount /mnt/nvme-boot
sudo umount /mnt/nvme-root

echo "[i] Migration complete!"
echo ""
echo "[!] Next steps:"
echo "    1. Power off the Pi: sudo poweroff"
echo "    2. Remove the SD card"
echo "    3. Power on the Pi (it will boot from NVMe)"
echo "    4. SSH back in and verify with: lsblk"
echo "    5. Run the rest of the setup scripts"
echo ""
read -p "Power off now? (yes/no): " -r
if [[ $REPLY =~ ^yes$ ]]; then
  sudo poweroff
fi

