#!/bin/bash
set -e

# Description: installs RAUC and config files into both rootfs partitions using chroot + QEMU

OUTPUT_DIR="artifacts"
IMG_NAME="disk.img"
IMAGE="$OUTPUT_DIR/$IMG_NAME"
MOUNT_BASE="$OUTPUT_DIR/mounts"

UTIL_DIR="utils"
CERT="$UTIL_DIR/ca.cert.pem"
SERVICE="$UTIL_DIR/rauc-mark-good.service"
CONF="$UTIL_DIR/system.conf"

QEMU_STATIC_BIN="/usr/bin/qemu-aarch64-static"

# Check for required files
for file in "$CERT" "$SERVICE" "$CONF"; do
  if [[ ! -f "$file" ]]; then
    echo "[!] Required file missing: $file"
    exit 1
  fi
done

if [[ ! -x "$QEMU_STATIC_BIN" ]]; then
  echo "[!] QEMU static binary not found at $QEMU_STATIC_BIN. Exiting."
  exit 1
fi

echo "[+] Creating mount base directory: $MOUNT_BASE"
mkdir -p "$MOUNT_BASE"

echo "[+] Attaching loop device to $IMAGE"
LOOP_DEVICE=$(sudo losetup --show -Pf "$IMAGE")
echo "[+] Loop device attached: $LOOP_DEVICE"

echo "[+] Detecting partitions..."
PARTS=($(lsblk -ln -o NAME "$LOOP_DEVICE" | grep "^$(basename "$LOOP_DEVICE")p"))
echo "[*] Found partitions: ${PARTS[*]}"

NUM_PARTS=${#PARTS[@]}
if ((NUM_PARTS < 3)); then
  echo "[!] Expected at least 3 partitions, found $NUM_PARTS. Exiting."
  sudo losetup -d "$LOOP_DEVICE"
  exit 1
fi

PART1="/dev/${PARTS[1]}"
PART2="/dev/${PARTS[2]}"
echo "[+] Using rootfs partitions: $PART1 and $PART2"

for part in "$PART1" "$PART2"; do
  mount_point="$MOUNT_BASE/$(basename $part)"
  echo "[+] Mounting $part to $mount_point"
  mkdir -p "$mount_point"
  sudo mount "$part" "$mount_point"

  echo "[+] Copying QEMU static binary to $mount_point/usr/bin/"
  sudo mkdir -p "$mount_point/usr/bin"
  sudo cp "$QEMU_STATIC_BIN" "$mount_point/usr/bin/"

  echo "[+] Binding chroot filesystems..."
  for fs in dev dev/pts proc sys run; do
    sudo mount --bind "/$fs" "$mount_point/$fs"
  done

  echo "[+] Ensuring /etc/resolv.conf for DNS inside chroot"
  sudo cp /etc/resolv.conf "$mount_point/etc/resolv.conf"

  echo "[+] Installing RAUC in chroot..."
  sudo chroot "$mount_point" /usr/bin/qemu-aarch64-static /bin/bash -c "
    apt update &&
    apt install -y rauc &&
    mkdir -p /etc/rauc &&
    mkdir -p /etc/systemd/system &&
    mkdir -p /etc/systemd/system/rauc-mark-good:.service.d
  "

  echo "[+] Copying configuration files..."
  sudo cp "$CERT" "$mount_point/etc/rauc/"
  sudo cp "$SERVICE" "$mount_point/etc/systemd/system/"
  sudo cp "$CONF" "$mount_point/etc/rauc/"

  echo "[+] Unmounting chroot filesystems"
  for fs in run sys proc dev/pts dev; do
    sudo umount "$mount_point/$fs" || true
  done

  echo "[+] Unmounting $mount_point"
  sudo umount "$mount_point"
done

echo "[+] Detaching loop device $LOOP_DEVICE"
sudo losetup -d "$LOOP_DEVICE"

echo "[✔] RAUC and config installed on both rootfs partitions."
