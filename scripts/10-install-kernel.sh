#!/bin/bash
set -e

# Description: writes linux Image to boot partition

OUTPUT_DIR="artifacts"
IMG_NAME="disk.img"
IMAGE="$OUTPUT_DIR/$IMG_NAME"
MOUNT_BASE="$OUTPUT_DIR/mounts"
KERNEL_IMAGE="$OUTPUT_DIR/Image"
DTB="$OUTPUT_DIR/imx93-11x11-evk.dtb"

echo "[+] Creating mount base directory: $MOUNT_BASE"
mkdir -p "$MOUNT_BASE"

echo "[+] Attaching loop device to $IMAGE"
LOOP_DEVICE=$(sudo losetup --show -Pf "$IMAGE")
echo "[+] Loop device attached: $LOOP_DEVICE"

echo "[+] Detecting partitions..."
PARTS=($(lsblk -ln -o NAME "$LOOP_DEVICE" | grep "^$(basename $LOOP_DEVICE)p"))
echo "[*] Found partitions: ${PARTS[*]}"

NUM_PARTS=${#PARTS[@]}
echo "[+] Found $NUM_PARTS partition(s)"

if ((NUM_PARTS < 2)); then
  echo "[!] Expected at least 2 partitions, found $NUM_PARTS. Exiting."
  sudo losetup -d "$LOOP_DEVICE"
  exit 1
fi

PART0="/dev/${PARTS[0]}"
echo "[+] Using the rootfs partition: $PART0"

mount_point="${MOUNT_BASE}/$(basename $PART0)"
echo "[+] Mounting $PART0 to $mount_point"
mkdir -p "$mount_point"
sudo mount "$PART0" "$mount_point"

echo "[+] Copying kernel image to $mount_point/"
sudo cp "$KERNEL_IMAGE" "$mount_point"

echo "[+] Copying .dtb to $mount_point/"
sudo cp "$DTB" "$mount_point"

echo "[+] Unmounting $mount_point"
sudo umount "$mount_point"

echo "[+] Detaching loop device $LOOP_DEVICE"
sudo losetup -d "$LOOP_DEVICE"

echo "[✔] Done."
