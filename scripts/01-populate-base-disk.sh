#!/bin/bash
set -e

# Description: Writes base Debian rootfs files to our two rootfs partitions
# on a prepared disk image (with bootloader already in place)

OUTPUT_DIR="artifacts"
IMG_NAME="disk.img"
IMAGE="$OUTPUT_DIR/$IMG_NAME"
MOUNT_BASE="$OUTPUT_DIR/mounts"
QEMU_STATIC_BIN="/usr/bin/qemu-aarch64-static"

# Sanity check for required tools
for tool in debootstrap losetup mount umount qemu-aarch64-static; do
  if ! command -v "$tool" &>/dev/null; then
    echo "[!] Required tool '$tool' not found. Please install it."
    exit 1
  fi
done

# Cleanup on exit
LOOP_DEVICE=""
PARTS=()

cleanup() {
  echo "[*] Cleaning up..."
  if [[ -n "$LOOP_DEVICE" && -b "$LOOP_DEVICE" ]]; then
    echo "    Attempting to unmount and detach $LOOP_DEVICE..."
    for part in "${PARTS[@]}"; do
      mount_point="$MOUNT_BASE/$(basename "$part")"
      if [[ -d "$mount_point" ]]; then
        for sub in dev/pts dev proc sys run; do
          if mountpoint -q "$mount_point/$sub"; then
            echo "    Unmounting $mount_point/$sub"
            sudo umount "$mount_point/$sub" || true
          fi
        done
        if mountpoint -q "$mount_point"; then
          echo "    Unmounting $mount_point"
          sudo umount "$mount_point" || true
        fi
      fi
    done
    echo "    Detaching loop device $LOOP_DEVICE"
    sudo losetup -d "$LOOP_DEVICE" || true
  fi
}
trap cleanup EXIT

echo "[+] Writing flash.bin at 32 KiB offset..."
sudo dd if="$OUTPUT_DIR/flash.bin" of="$IMAGE" bs=1K seek=32 conv=notrunc,fsync

echo "[+] Creating mount base directory: $MOUNT_BASE"
mkdir -p "$MOUNT_BASE"

echo "[+] Attaching loop device to $IMAGE"
LOOP_DEVICE=$(sudo losetup --show -Pf "$IMAGE")
sleep 1
sudo partprobe "$LOOP_DEVICE"
echo "    -> $LOOP_DEVICE"

# Detect partitions
PARTS=($(lsblk -ln -o NAME "/dev/$(basename "$LOOP_DEVICE")" | grep "^$(basename "$LOOP_DEVICE")p" | sed 's|^|/dev/|'))
NUM_PARTS=${#PARTS[@]}
echo "[*] Found $NUM_PARTS partition(s): ${PARTS[*]}"

if ((NUM_PARTS < 3)); then
  echo "[!] Expected at least 3 partitions (BOOT, rootfsA, rootfsB). Exiting."
  exit 1
fi

PART1="${PARTS[1]}" # rootfsA
PART2="${PARTS[2]}" # rootfsB
echo "[+] Using rootfs partitions:"
echo "    rootfsA = $PART1"
echo "    rootfsB = $PART2"

# Loop through rootfsA and rootfsB
for part in "$PART1" "$PART2"; do
  mount_point="$MOUNT_BASE/$(basename "$part")"
  echo "[+] Mounting $part to $mount_point"
  sudo mkdir -p "$mount_point"
  sudo mount "$part" "$mount_point"

  echo "[+] Copying QEMU static binary to $mount_point/usr/bin/"
  sudo mkdir -p "$mount_point/usr/bin"
  sudo cp "$QEMU_STATIC_BIN" "$mount_point/usr/bin/"

  echo "[*] Running first stage debootstrap on $part"
  sudo debootstrap --arch=arm64 --foreign stable "$mount_point" http://deb.debian.org/debian

  echo "[+] Setting up chroot environment for $mount_point"
  sudo mount --bind /dev "$mount_point/dev"
  sudo mount --bind /dev/pts "$mount_point/dev/pts"
  sudo mount --bind /proc "$mount_point/proc"
  sudo mount --bind /sys "$mount_point/sys"
  sudo mount --bind /run "$mount_point/run"

  echo "[*] Running second stage debootstrap in chroot"
  sudo chroot "$mount_point" /usr/bin/qemu-aarch64-static /bin/bash -c "/debootstrap/debootstrap --second-stage"

  echo "[+] Setting root password to 'root'"
  sudo chroot "$mount_point" /usr/bin/qemu-aarch64-static /bin/bash -c "echo 'root:root' | chpasswd"

  echo "[+] Cleaning up chroot environment for $mount_point"
  for sub in dev/pts dev proc sys run; do
    if mountpoint -q "$mount_point/$sub"; then
      echo "    Unmounting $mount_point/$sub"
      sudo umount "$mount_point/$sub"
    fi
  done

  echo "[+] Unmounting $mount_point"
  sudo umount "$mount_point"
done

echo "[✔] Done. Disk image is populated with base rootfs on both partitions."
