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
sudo apt install -y rsync parted

echo "[i] Unmounting NVMe if mounted..."
sudo umount ${NVME_DEVICE}* 2>/dev/null || true

echo "[i] Wiping NVMe device..."
sudo wipefs -a ${NVME_DEVICE}
sudo blkdiscard ${NVME_DEVICE} 2>/dev/null || true

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
sudo rsync -axHAWX --info=progress2 /boot/firmware/ /mnt/nvme-boot/

echo "[i] Copying root filesystem (this may take 5-10 minutes)..."
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
PARTUUID=${ROOT_UUID}  /            ext4   defaults,noatime  0 1
PARTUUID=${BOOT_UUID}  /boot/firmware  vfat   defaults          0 2
EOF

echo "[i] Updating boot configuration..."

# Update cmdline.txt if it exists
if [[ -f /mnt/nvme-boot/cmdline.txt ]]; then
  sudo sed -i "s/root=[^ ]*/root=PARTUUID=${ROOT_UUID}/" /mnt/nvme-boot/cmdline.txt
  echo "[i] Updated cmdline.txt with new root UUID"
else
  echo "[!] Warning: cmdline.txt not found in boot partition"
  echo "[i] Checking boot partition contents..."
  ls -la /mnt/nvme-boot/
  echo "[i] This might be normal for some Ubuntu configurations"
fi

# Create or update config.txt for Pi 5 NVMe boot
echo "[i] Configuring Pi 5 for NVMe boot..."
sudo tee /mnt/nvme-boot/config.txt >/dev/null <<EOF
# Pi 5 NVMe boot configuration
[all]
# Enable NVMe boot
program_usb_boot_mode=1
program_usb_boot_timeout=1

# Disable Bluetooth to free up GPIO
dtoverlay=disable-bt

# Enable UART
enable_uart=1

# GPU memory split
gpu_mem=16

# Boot order: try NVMe first, then SD card
boot_order=0xf41
EOF

# Create usercfg.txt for additional Pi 5 settings
sudo tee /mnt/nvme-boot/usercfg.txt >/dev/null <<EOF
# Pi 5 user configuration
program_usb_boot_mode=1
program_usb_boot_timeout=1
EOF

echo "[i] Pi 5 NVMe boot configuration created"

# Ensure Pi 5 bootloader is up to date
echo "[i] Updating Pi 5 bootloader..."
if [[ -f /mnt/nvme-boot/firmware/start4.elf ]]; then
  echo "[i] Pi 4 bootloader detected, copying Pi 5 bootloader..."
  # Copy Pi 5 bootloader files if available
  if [[ -f /boot/firmware/firmware/start4.elf ]]; then
    sudo cp /boot/firmware/firmware/* /mnt/nvme-boot/firmware/ 2>/dev/null || true
  fi
else
  echo "[i] Bootloader files will be copied from current system"
fi

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

