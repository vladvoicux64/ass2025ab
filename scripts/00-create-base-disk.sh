#!/bin/bash
set -e

cleanup() {
  echo "[*] Cleaning up..."
  if [[ -n "$LOOP_DEV" ]]; then
    for i in {1..4}; do
      MOUNT_POINT=$(lsblk -no MOUNTPOINT "${LOOP_DEV}p$i")
      if [[ -n "$MOUNT_POINT" ]]; then
        echo "    Unmounting ${LOOP_DEV}p$i from $MOUNT_POINT..."
        sudo umount "${LOOP_DEV}p$i"
      fi
    done

    echo "    Detaching loop device $LOOP_DEV..."
    sudo losetup -d "$LOOP_DEV" || true
  fi
}
trap cleanup EXIT

# Description: Creates a disk image with space for a bootloader and four partitions:
# BOOT (FAT32), rootfsA (ext4), rootfsB (ext4), and data (ext4)

OUTPUT_DIR="artifacts"
IMG_NAME="disk.img"
IMG_PATH="$OUTPUT_DIR/$IMG_NAME"

IMG_SIZE_MB=4096 # Total image size
RESERVED_MB=10   # Reserved space at the beginning for bootloader/SPL
BOOT_MB=256      # Size of BOOT partition
ROOTFS_MB=1536   # Size of each rootfs partition (A and B)

# Compute partition layout
PART1_START_MB=$((RESERVED_MB))
PART1_END_MB=$((PART1_START_MB + BOOT_MB))
PART2_END_MB=$((PART1_END_MB + ROOTFS_MB))
PART3_END_MB=$((PART2_END_MB + ROOTFS_MB))

# Sanity check: ensure the first 3 partitions leave enough space for a 4th
if ((PART3_END_MB >= IMG_SIZE_MB - 1)); then
  echo "[!] ERROR: Not enough space for partition 4. Increase IMG_SIZE_MB."
  echo "    Needed end of partition 3: ${PART3_END_MB} MiB"
  echo "    Image size: ${IMG_SIZE_MB} MiB"
  exit 1
fi

# Print partition layout
echo "[*] Partition layout:"
echo "    Reserved (bootloader): 0 – ${RESERVED_MB} MiB"
echo "    BOOT (FAT32):          ${PART1_START_MB} – ${PART1_END_MB} MiB"
echo "    rootfsA (ext4):        ${PART1_END_MB} – ${PART2_END_MB} MiB"
echo "    rootfsB (ext4):        ${PART2_END_MB} – ${PART3_END_MB} MiB"
echo "    data (ext4):           ${PART3_END_MB} – ${IMG_SIZE_MB} MiB (remaining space)"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "[+] Creating ${IMG_SIZE_MB}MB disk image at '$IMG_PATH'..."
dd if=/dev/zero of="$IMG_PATH" bs=1M count="$IMG_SIZE_MB"

echo "[+] Creating partition table..."
parted "$IMG_PATH" --script -- \
  mklabel msdos \
  mkpart primary fat32 "${PART1_START_MB}"MiB "${PART1_END_MB}"MiB \
  mkpart primary ext4 "${PART1_END_MB}"MiB "${PART2_END_MB}"MiB \
  mkpart primary ext4 "${PART2_END_MB}"MiB "${PART3_END_MB}"MiB \
  mkpart primary ext4 "${PART3_END_MB}"MiB 100%

echo "[+] Attaching loop device..."
LOOP_DEV=$(sudo losetup --find --show --partscan "$IMG_PATH")
echo "    -> $LOOP_DEV"

# Wait for kernel to register partitions
sleep 1
sudo partprobe "$LOOP_DEV"

echo "[+] Formatting partitions..."
sudo mkfs.vfat -n BOOT "${LOOP_DEV}p1"
sudo mkfs.ext4 -L rootfsA "${LOOP_DEV}p2"
sudo mkfs.ext4 -L rootfsB "${LOOP_DEV}p3"
sudo mkfs.ext4 -L data "${LOOP_DEV}p4"

echo "[+] Disk image '$IMG_PATH' is ready:"
lsblk "$LOOP_DEV"

echo "[✔] Done."
