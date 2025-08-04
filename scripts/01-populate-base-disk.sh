#!/bin/bash
set -e

# Description: writes base Debian rootfs files to our two partitions

OUTPUT_DIR="artifacts"
IMG_NAME="disk.img"
IMAGE="$OUTPUT_DIR/$IMG_NAME"
MOUNT_BASE="$OUTPUT_DIR/mounts"

echo "[+] Creating mount base directory: $MOUNT_BASE"
mkdir -p "$MOUNT_BASE"

echo "[+] Attaching loop device to $IMAGE"
LOOP_DEVICE=$(sudo losetup --show -Pf "$IMAGE")
echo "[+] Loop device attached: $LOOP_DEVICE"

echo "[+] Detecting partitions..."
PARTS=($(lsblk -ln -o NAME "$LOOP_DEVICE" | grep "^$(basename "$LOOP_DEVICE")p"))
echo "[*] Found partitions: ${PARTS[*]}"

NUM_PARTS=${#PARTS[@]}
echo "[+] Found $NUM_PARTS partition(s)"

if ((NUM_PARTS < 2)); then
  echo "[!] Expected at least 2 partitions, found $NUM_PARTS. Exiting."
  sudo losetup -d "$LOOP_DEVICE"
  exit 1
fi

PART1="/dev/${PARTS[1]}"
PART2="/dev/${PARTS[2]}"
echo "[+] Using the rootfs partitions: $PART1 and $PART2"

QEMU_STATIC_BIN="/usr/bin/qemu-aarch64-static"
if [[ ! -x "$QEMU_STATIC_BIN" ]]; then
  echo "[!] QEMU static binary not found at $QEMU_STATIC_BIN. Exiting."
  sudo losetup -d "$LOOP_DEVICE"
  exit 1
fi

for part in "$PART1" "$PART2"; do
  mount_point="${MOUNT_BASE}/$(basename $part)"
  echo "[+] Mounting $part to $mount_point"
  mkdir -p "$mount_point"
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

  echo "[+] Unmounting chroot filesystems"
  sudo umount "$mount_point/dev/pts" || true
  sudo umount "$mount_point/dev" || true
  sudo umount "$mount_point/proc" || true
  sudo umount "$mount_point/sys" || true
  sudo umount "$mount_point/run" || true

  echo "[+] Unmounting $mount_point"
  sudo umount "$mount_point"
done

echo "[+] Detaching loop device $LOOP_DEVICE"
sudo losetup -d "$LOOP_DEVICE"

echo "[✔] Done."
