# 🛠️ RAUC Bootable Image Workshop (Summer School Edition)

Welcome to the RAUC Image Creation exercise!  
You will create a bootable disk image for an embedded system with multiple partitions (boot, rootfsA, rootfsB, data), install a kernel, configure U-Boot with environment support, and install **RAUC** in both rootfs partitions.

This is a hands-on, exploratory session — **some tasks are left for you to figure out**, but guided to ensure success.

---

## 🧱 Directory Structure

You should start with:

```
root/
├── artifacts/
│   ├── linux.itb             # Kernel image
│   ├── uboot.env             # U-Boot environment variables (just the var file)
├── utils/
│   ├── ca.cert.pem
│   ├── rauc-mark-good.service
│   ├── system.conf
│   └── fstab                 # Optional custom fstab
├── scripts/
│   ├── 00-create-base-disk.sh
│   ├── 01-populate-base-disk.sh
│   ├── 05-modify-bootcmd.sh
│   ├── 10-install-kernel-env.sh
│   └── 15-install-rauc.sh
├── run-all.sh               # Will run all scripts in order
└── README.md                # This file
```

---

## ✅ Pre-Requisites

Make sure you have these packages installed on your host system:

```bash
sudo apt install qemu-user-static binfmt-support debootstrap parted dosfstools e2fsprogs u-boot-tools uuu
```

Then, check that `binfmt_misc` is active and register the QEMU handler for aarch64 if not:

```bash
grep aarch64 /proc/sys/fs/binfmt_misc/qemu-aarch64
```

If it’s empty, run:

```bash
sudo su
echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff:/usr/bin/qemu-aarch64-static:CF' > /proc/sys/fs/binfmt_misc/register
exit
```

---

## 🧩 Step-by-Step Instructions

You’ll be running scripts in `./scripts`, either one by one or all together via `./run-all.sh`.  
**The scripts are templates** — you may need to complete missing parts.

---

### 1️⃣ Create the base disk image

📄 File: `00-create-base-disk.sh`

Your task:
- Use `truncate` or `dd` to allocate the image.
- Create a GPT partition table.
- Add partitions for:
  - BOOT (FAT32, ~64MB)
  - rootfsA (ext4)
  - rootfsB (ext4)
  - data (ext4)

💡 Use `parted`, `mkfs.*`, and `e2label`.

<details>
<summary>💡 Hint (click to expand)</summary>

Use `parted -s $IMAGE` and `mkfs.vfat`/`mkfs.ext4` on loop devices via `losetup`.

</details>

---

### 2️⃣ Populate the rootfs partitions

📄 File: `01-populate-base-disk.sh`

Use `debootstrap` to install a minimal Debian/Ubuntu base system into both rootfsA and rootfsB.

Tasks:
- Mount the partitions created previously
- Run `debootstrap` twice (for each rootfs)
- Set the correct labels and ensure unique mount points

<details>
<summary>💡 Hint (click to expand)</summary>

Use the same base system (e.g., `debootstrap --arch=arm64 jammy`) into both partitions.

</details>

---

### 3️⃣ Modify U-Boot bootcmd

📄 File: `05-modify-bootcmd.sh`


Tasks:
- Clone [imx-image-builder](https://github.com/freemangordon/imx-image-builder) or use a local copy (I've included it as a submodule for you).
- Run the script, that repalces bootcmd with the provided copy.
- Regenerate `flash.bin`.

<details>
<summary>💡 Hint (click to expand)</summary>

Add logic like:

```bash
if test "$rauc_status" = "B"; then
  setenv rootpart rootfsB
else
  setenv rootpart rootfsA
fi
```

Then `make uboot` and `make imx_mkimage`.

</details>

---

### 4️⃣ Install Kernel and U-Boot env

📄 File: `10-install-kernel-env.sh`

What’s handled:
- Mount the BOOT partition
- Copy in:
  - `linux.itb` (kernel image)
  - `uboot.env` (default env file)

✅ This script is mostly complete, **you can read and understand it** — no changes needed unless paths differ.

---

### 5️⃣ Install RAUC and Configuration

📄 File: `15-install-rauc.sh`

This script will:
- Mount both rootfsA and rootfsB
- Use QEMU and chroot to install:
  - `rauc`
  - your `ca.cert.pem`
  - `system.conf`
  - `rauc-mark-good.service`
- Setup `/etc/fw_env.config`, `fstab`, and enable systemd services

Tasks:
- Ensure QEMU works inside chroot
- Make sure `rauc.service` is enabled in both roots

✅ Script is complete. Feel free to read and understand it.

---

## ⚙️ U-Boot and Flashing the Board

Now, let’s put everything together.

### ⚙️ Rebuild U-Boot and Flash Image

From inside the imx-image-builder directory:

```bash
make uboot
make imx_mkimage
```

⚠️ Ensure U-Boot is configured to load the env file from FAT:
```bash
make menuconfig
# Enable: Environment -> Environment in a FAT filesystem
```

Then generate `flash.bin` and flash it:

```bash
sudo ./uuu -b emmc_all flash.bin artifacts/disk.img
```

---

### 🧪 Boot and Login

Boot your board.  
Default login:

```bash
Username: root
Password: root
```

Check:

```bash
mount | grep rootfs
cat /etc/rauc/system.conf
```

---

## 🧼 Cleanup (Optional)

To unmount everything and clean loop devices:

```bash
sudo losetup -D
```

---

## 🧠 Bonus Challenges

- Create a `.raucb` update bundle
- Trigger an A/B switch and simulate a failed update
- Add a watchdog or rollback mechanism

---

Enjoy! 🎉  
If you get stuck, ask a mentor or check the script source.
