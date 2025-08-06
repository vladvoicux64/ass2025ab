#!/bin/bash
set -e

# Description: Installs RAUC and config files into both rootfs partitions using chroot + QEMU

OUTPUT_DIR="artifacts"
IMG_NAME="disk.img"
IMAGE="$OUTPUT_DIR/$IMG_NAME"
MOUNT_BASE="$OUTPUT_DIR/mounts"

UTIL_DIR="utils"
CERT="$UTIL_DIR/ca.cert.pem"
SERVICE="$UTIL_DIR/rauc-mark-good.service"
CONF="$UTIL_DIR/system.conf"
FSTAB="$UTIL_DIR/fstab"

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

BOOT_PART="/dev/${PARTS[0]}"
PART1="/dev/${PARTS[1]}"
PART2="/dev/${PARTS[2]}"
echo "[+] Using rootfs partitions: $PART1 and $PART2"
echo "[+] Using boot partition: $BOOT_PART"

# Function to generate a default fstab
generate_default_fstab() {
  cat <<EOF
LABEL=rootfsA  /      ext4 defaults 0 1
LABEL=BOOT     /boot  vfat defaults 0 2
LABEL=data     /data  ext4 defaults 0 2
EOF
}

for part in "$PART1" "$PART2"; do
  mount_point="$MOUNT_BASE/$(basename "$part")"
  boot_mount="$MOUNT_BASE/boot"

  echo "[+] Mounting rootfs: $part to $mount_point"
  mkdir -p "$mount_point"
  sudo mount "$part" "$mount_point"

  echo "[+] Mounting boot partition $BOOT_PART to $boot_mount"
  mkdir -p "$boot_mount"
  sudo mount "$BOOT_PART" "$boot_mount"

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
    set -e
    apt update &&
    apt install -y rauc rauc-service u-boot-tools
  "

  echo "[+] Creating needed directories inside mounted rootfs"
  sudo mkdir -p "$mount_point/etc/rauc"
  sudo mkdir -p "$mount_point/etc/systemd/system/rauc-mark-good.service.d"

  echo "[+] Copying configuration files..."
  sudo cp "$CERT" "$mount_point/etc/rauc/"
  sudo cp "$CONF" "$mount_point/etc/rauc/"
  sudo cp "$SERVICE" "$mount_point/etc/systemd/system/"

  echo "[+] Installing fstab..."
  if [[ -f "$FSTAB" ]]; then
    echo "    Using user-provided $FSTAB"
    sudo cp "$FSTAB" "$mount_point/etc/fstab"
  else
    echo "    Generating default fstab for RAUC setup"
    generate_default_fstab | sudo tee "$mount_point/etc/fstab" >/dev/null
  fi

  echo "[+] Creating /etc/fw_env.config pointing to /boot/uboot.env"
  echo "/boot/uboot.env 0x0 0x4000" | sudo tee "$mount_point/etc/fw_env.config" >/dev/null

  echo "[+] Enabling rauc and rauc-mark-good services..."
  systemd_dir="$mount_point/etc/systemd/system"
  sudo mkdir -p "$systemd_dir/multi-user.target.wants"

  if [[ -f "$systemd_dir/rauc.service" ]]; then
    sudo ln -sf "../rauc.service" "$systemd_dir/multi-user.target.wants/rauc.service"
    echo "  Enabled rauc.service in $part"
  else
    echo "  Warning: rauc.service not found in $part"
  fi

  if [[ -f "$systemd_dir/rauc-mark-good.service" ]]; then
    sudo ln -sf "../rauc-mark-good.service" "$systemd_dir/multi-user.target.wants/rauc-mark-good.service"
    echo "  Enabled rauc-mark-good.service in $part"
  else
    echo "  Warning: rauc-mark-good.service not found in $part"
  fi

  echo "[+] Unmounting chroot filesystems"
  for fs in run sys proc dev/pts dev; do
    sudo umount "$mount_point/$fs" || true
  done

  echo "[+] Unmounting rootfs $mount_point"
  sudo umount "$mount_point"

  echo "[+] Unmounting boot partition $boot_mount"
  sudo umount "$boot_mount"
done

echo "[+] Detaching loop device $LOOP_DEVICE"
sudo losetup -d "$LOOP_DEVICE"

echo "[✔] RAUC, config files, services, fstab, and fw_env.config set up correctly on both rootfs partitions."
