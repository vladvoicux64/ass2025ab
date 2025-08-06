#!/bin/bash
set -e

# Description: Writes Linux kernel image and U-Boot environment to the BOOT partition

OUTPUT_DIR="artifacts"
IMG_NAME="disk.img"
IMAGE="$OUTPUT_DIR/$IMG_NAME"
MOUNT_BASE="$OUTPUT_DIR/mounts"
KERNEL_IMAGE="$OUTPUT_DIR/linux.itb"
ENV_FILE="$OUTPUT_DIR/uboot.env"

# Sanity checks
for f in "$IMAGE" "$KERNEL_IMAGE" "$ENV_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "[!] Required file '$f' not found. Exiting."
    exit 1
  fi
done

echo "[+] Creating mount base directory: $MOUNT_BASE"
mkdir -p "$MOUNT_BASE"

# Cleanup on exit
LOOP_DEVICE=""
PARTS=()

cleanup() {
  echo "[*] Cleaning up..."
  if [[ -n "$LOOP_DEVICE" && -b "$LOOP_DEVICE" ]]; then
    mount_point="$MOUNT_BASE/$(basename "$PARTS")"
    if mountpoint -q "$mount_point"; then
      echo "    Unmounting $mount_point"
      sudo umount "$mount_point" || true
    fi
    echo "    Detaching loop device $LOOP_DEVICE"
    sudo losetup -d "$LOOP_DEVICE" || true
  fi
}
trap cleanup EXIT

echo "[+] Attaching loop device to $IMAGE"
LOOP_DEVICE=$(sudo losetup --show -Pf "$IMAGE")
echo "    -> $LOOP_DEVICE"

sleep 1
sudo partprobe "$LOOP_DEVICE"

# Detect partitions
PARTS=($(lsblk -ln -o NAME "/dev/$(basename "$LOOP_DEVICE")" | grep "^$(basename "$LOOP_DEVICE")p" | sed 's|^|/dev/|'))
NUM_PARTS=${#PARTS[@]}
echo "[*] Found $NUM_PARTS partition(s): ${PARTS[*]}"

if ((NUM_PARTS < 1)); then
  echo "[!] Expected at least 1 partition (BOOT). Exiting."
  exit 1
fi

PART0="${PARTS[0]}" # BOOT partition
echo "[+] Using BOOT partition: $PART0"

mount_point="${MOUNT_BASE}/$(basename "$PART0")"
echo "[+] Mounting $PART0 to $mount_point"
mkdir -p "$mount_point"
sudo mount "$PART0" "$mount_point"

echo "[+] Copying kernel image to $mount_point/"
sudo cp "$KERNEL_IMAGE" "$mount_point"

echo "[+] Copying environment file to $mount_point/"
sudo cp "$ENV_FILE" "$mount_point"

echo "[✔] Done. BOOT partition has been updated."
