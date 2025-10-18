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

# --- Safety prompt ----------------------------------------------------------
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

# --- Setup cleanup trap -----------------------------------------------------
trap 'sudo umount /mnt/nvme-boot 2>/dev/null || true; sudo umount /mnt/nvme-root 2>/dev/null || true' EXIT

# --- Preparation ------------------------------------------------------------
echo "[i] Installing required tools..."
sudo apt update
sudo apt install -y rsync parted rpi-eeprom nvme-cli

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
sudo nvme id-ctrl ${NVME_DEVICE} 2>/dev/null || echo "[!] Warning: Cannot read controller info"

echo "[i] Checking power supply status:"
vcgencmd get_throttled 2>/dev/null || echo "[!] Cannot check power status"

echo "[i] Testing basic read capability..."
if ! sudo dd if=${NVME_DEVICE} of=/dev/null bs=1M count=1 2>/dev/null; then
  echo "[!] NVMe read test failed. Hardware issue likely."
  exit 1
fi

# --- Partitioning -----------------------------------------------------------
echo "[i] Wiping NVMe device..."
sudo wipefs -a ${NVME_DEVICE} || true
sudo blkdiscard ${NVME_DEVICE} 2>/dev/null || echo "[!] blkdiscard failed (often harmless)"

echo "[i] Creating GPT partition table..."
sudo parted -s ${NVME_DEVICE} mklabel gpt
sudo parted -s ${NVME_DEVICE} mkpart primary fat32 0% 512MB
sudo parted -s ${NVME_DEVICE} mkpart primary ext4 512MB 100%
sudo parted -s ${NVME_DEVICE} set 1 boot on
sudo partprobe ${NVME_DEVICE}
sleep 2

BOOT_PART="${NVME_DEVICE}p1"
ROOT_PART="${NVME_DEVICE}p2"

if [[ ! -b ${BOOT_PART} || ! -b ${ROOT_PART} ]]; then
  echo "[!] Error: Partitioning failed."
  exit 1
fi

echo "[i] Formatting partitions..."
sudo mkfs.vfat -F 32 -n BOOT ${BOOT_PART}
sudo mkfs.ext4 -F -L writable ${ROOT_PART}

# --- Mount and copy ---------------------------------------------------------
echo "[i] Mounting NVMe partitions..."
sudo mkdir -p /mnt/nvme-{boot,root}
sudo mount ${BOOT_PART} /mnt/nvme-boot
sudo mount ${ROOT_PART} /mnt/nvme-root

echo "[i] Copying boot and root files..."
if [[ -d /boot/firmware && -n "$(ls -A /boot/firmware 2>/dev/null)" ]]; then
  echo "[i] Detected Ubuntu-style boot layout"
  BOOT_SRC="/boot/firmware"
else
  echo "[i] Detected Raspberry Pi OS-style boot layout"
  BOOT_SRC="/boot"
fi

sudo rsync -axHAWX --info=progress2 ${BOOT_SRC}/ /mnt/nvme-boot/
sudo rsync -axHAWX --info=progress2 \
  --exclude={"/mnt/*","/proc","/sys","/dev","/tmp","/run"} / /mnt/nvme-root/

echo "[i] Creating system directories on NVMe..."
sudo mkdir -p /mnt/nvme-root/{proc,sys,dev,tmp}

# --- fstab / UUIDs ----------------------------------------------------------
BOOT_UUID=$(sudo blkid -s PARTUUID -o value ${BOOT_PART})
ROOT_UUID=$(sudo blkid -s PARTUUID -o value ${ROOT_PART})

sudo tee /mnt/nvme-root/etc/fstab >/dev/null <<EOF
PARTUUID=${ROOT_UUID}  /               ext4   defaults,noatime  0 1
PARTUUID=${BOOT_UUID}  /boot/firmware  vfat   defaults          0 2
EOF

# --- Kernel / initrd / DTBs -------------------------------------------------
echo "[i] Preparing boot files..."
KERNEL_IMG=$(ls ${BOOT_SRC}/vmlinuz* 2>/dev/null | sort -V | tail -1 || true)
INITRD_IMG=$(ls ${BOOT_SRC}/initrd.img* 2>/dev/null | sort -V | tail -1 || true)
if [[ -f "$KERNEL_IMG" ]]; then
  sudo cp "$KERNEL_IMG" /mnt/nvme-boot/kernel_2712.img
fi
if [[ -f "$INITRD_IMG" ]]; then
  sudo cp "$INITRD_IMG" /mnt/nvme-boot/initrd.img
fi

sudo mkdir -p /mnt/nvme-boot/overlays
sudo cp -r ${BOOT_SRC}/bcm2712* /mnt/nvme-boot/ 2>/dev/null || true
sudo cp -r ${BOOT_SRC}/overlays/* /mnt/nvme-boot/overlays/ 2>/dev/null || true

# --- cmdline.txt ------------------------------------------------------------
if [[ -f /mnt/nvme-boot/cmdline.txt ]]; then
  sudo sed -i "s/root=[^ ]*/root=PARTUUID=${ROOT_UUID}/" /mnt/nvme-boot/cmdline.txt
else
  echo "console=serial0,115200 console=tty1 root=PARTUUID=${ROOT_UUID} rootfstype=ext4 fsck.repair=yes rootwait quiet splash" \
    | sudo tee /mnt/nvme-boot/cmdline.txt >/dev/null
fi

# --- config.txt / usercfg.txt ----------------------------------------------
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

sudo tee /mnt/nvme-boot/usercfg.txt >/dev/null <<EOF
# Additional user configuration
program_usb_boot_mode=1
program_usb_boot_timeout=1
EOF

# --- Firmware stubs recovery -----------------------------------------------
echo "[i] Ensuring mandatory firmware stubs..."
for fw in bootcode.bin start4.elf fixup4.dat armstub8-2712.bin; do
  if [[ ! -f /mnt/nvme-boot/$fw && -f ${BOOT_SRC}/$fw ]]; then
    sudo cp ${BOOT_SRC}/$fw /mnt/nvme-boot/ 2>/dev/null || true
  fi
done

# --- EEPROM configuration ---------------------------------------------------
echo "[i] Configuring EEPROM boot order for Pi 5..."
if command -v rpi-eeprom-config >/dev/null 2>&1; then
  TMP=$(mktemp)
  sudo rpi-eeprom-config >"$TMP"
  if ! grep -q '^BOOT_ORDER=' "$TMP"; then
    echo "BOOT_ORDER=0xf416" | sudo tee -a "$TMP" >/dev/null
  else
    sudo sed -i 's/^BOOT_ORDER=.*/BOOT_ORDER=0xf416/' "$TMP"
  fi
  sudo rpi-eeprom-config --apply "$TMP"
  rm "$TMP"
  echo "[i] EEPROM boot order configured successfully"
else
  echo "[!] rpi-eeprom-config not found; install with: sudo apt install rpi-eeprom"
fi

# --- Final verification -----------------------------------------------------
echo "[i] Verifying boot partition..."
for f in kernel_2712.img bcm2712-rpi-5-b.dtb armstub8-2712.bin start4.elf fixup4.dat config.txt cmdline.txt; do
  if [[ -f /mnt/nvme-boot/$f ]]; then
    echo " [OK] $f"
  else
    echo " [MISSING] $f"
  fi
done

echo "[i] Syncing filesystems..."
sync

# --- Cleanup and next steps -------------------------------------------------
sudo umount /mnt/nvme-boot
sudo umount /mnt/nvme-root
trap - EXIT

echo "[i] Migration complete!"
echo ""
echo "[!] Next steps:"
echo "    1. Power off the Pi: sudo poweroff"
echo "    2. Remove the SD card"
echo "    3. Boot from NVMe"
echo "    4. SSH in and run: lsblk"
echo "    5. Continue setup scripts"
echo ""
read -p "Power off now? (yes/no): " -r
if [[ $REPLY =~ ^yes$ ]]; then
  sudo poweroff
fi
