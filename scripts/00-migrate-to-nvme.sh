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
sudo parted -s ${NVME_DEVICE} mklabel gpt
sudo parted -s ${NVME_DEVICE} mkpart primary fat32 0% 512MB
sudo parted -s ${NVME_DEVICE} mkpart primary ext4 512MB 100%
sudo parted -s ${NVME_DEVICE} set 1 boot on

sleep 2
sudo partprobe ${NVME_DEVICE}
sleep 2

BOOT_PART="${NVME_DEVICE}p1"
ROOT_PART="${NVME_DEVICE}p2"

echo "[i] Formatting partitions..."
sudo mkfs.vfat -F 32 -n BOOT ${BOOT_PART}
sudo mkfs.ext4 -F -L writable ${ROOT_PART}

echo "[i] Mounting NVMe partitions..."
sudo mkdir -p /mnt/nvme-boot
sudo mkdir -p /mnt/nvme-root
sudo mount ${BOOT_PART} /mnt/nvme-boot
sudo mount ${ROOT_PART} /mnt/nvme-root

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
sudo sed -i "s/root=[^ ]*/root=PARTUUID=${ROOT_UUID}/" /mnt/nvme-boot/cmdline.txt

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

