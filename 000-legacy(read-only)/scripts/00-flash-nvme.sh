#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/utils.sh
load_env
detect_latest_lts
confirm_device

IMG_FILE="ubuntu-${UBUNTU_VERSION}-preinstalled-server-arm64+raspi.img.xz"
IMG_URL=${UBUNTU_IMG_URL:-"https://cdimage.ubuntu.com/releases/${UBUNTU_VERSION}/release/${IMG_FILE}"}

echo "[i] Downloading Ubuntu ${UBUNTU_VERSION} image..."
curl -L --retry 5 --continue-at - -o "${IMG_FILE}" "${IMG_URL}"

echo "[i] Verifying size..."
[[ $(stat -c%s "${IMG_FILE}") -gt 500000000 ]] || { echo "[!] Download failed or truncated."; exit 1; }

echo "[i] Decompressing..."
unxz -f "${IMG_FILE}"

IMG="${IMG_FILE%.xz}"
echo "[i] Writing image to ${NVME_DEVICE}..."
sudo umount "${NVME_DEVICE}"* 2>/dev/null || true
sudo blkdiscard "${NVME_DEVICE}" || true
sudo dd if="${IMG}" of="${NVME_DEVICE}" bs=4M status=progress conv=fsync
sync

echo "[i] Mounting boot partition..."
sudo mkdir -p /mnt/boot
sudo mount "${NVME_DEVICE}p1" /mnt/boot

echo "[i] Injecting cloud-init templates..."
envsubst < cloudinit/user-data.template | sudo tee /mnt/boot/user-data >/dev/null
envsubst < cloudinit/network-config.template | sudo tee /mnt/boot/network-config >/dev/null
envsubst < cloudinit/meta-data.template | sudo tee /mnt/boot/meta-data >/dev/null

sudo umount /mnt/boot
echo "Flash complete. Remove SD card and reboot."
