#!/bin/bash
set -e

# Description: creates a basic partitioned disk image to be filled with a bootloader, kernel and userland

OUTPUT_DIR="artifacts"
IMG_NAME="disk.img"
IMG_SIZE_MB=4096
BOOT_MB=256
ROOTFS_MB=1536

mkdir -p "$OUTPUT_DIR"
IMG_PATH="$OUTPUT_DIR/$IMG_NAME"

echo "[+] Creating ${IMG_SIZE_MB}MB disk image at '$IMG_PATH'..."
dd if=/dev/zero of="$IMG_PATH" bs=1M count="$IMG_SIZE_MB"

echo "[+] Creating partition table..."
parted "$IMG_PATH" --script -- \
  mklabel msdos \
  mkpart primary fat32 1MiB "$((1 + BOOT_MB))"MiB \
  mkpart primary ext4 "$((1 + BOOT_MB))"MiB "$((1 + BOOT_MB + ROOTFS_MB))"MiB \
  mkpart primary ext4 "$((1 + BOOT_MB + ROOTFS_MB))"MiB "$((1 + BOOT_MB + 2 * ROOTFS_MB))"MiB \
  mkpart primary ext4 "$((1 + BOOT_MB + 2 * ROOTFS_MB))"MiB 100%

echo "[+] Setting up loop device..."
LOOP_DEV=$(sudo losetup --find --show --partscan "$IMG_PATH")
echo "    -> $LOOP_DEV"

sleep 1 # Wait for partitions to show

echo "[+] Formatting..."
sudo mkfs.vfat -n BOOT "${LOOP_DEV}p1"
sudo mkfs.ext4 -L rootfsA "${LOOP_DEV}p2"
sudo mkfs.ext4 -L rootfsB "${LOOP_DEV}p3"
sudo mkfs.ext4 -L data "${LOOP_DEV}p4"

echo "[+] Disk image '$IMG_PATH' is ready:"
lsblk "$LOOP_DEV"

echo "[+] Detaching loop device..."
sudo losetup -d "$LOOP_DEV"

echo "[✔] Done."
