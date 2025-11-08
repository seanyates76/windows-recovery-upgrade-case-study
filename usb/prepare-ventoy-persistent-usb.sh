#!/usr/bin/env bash
# Create Ventoy USB with Ubuntu ISO + persistence + TestDisk
# Safe, single‑shot script — paste as one block.

set -euo pipefail
IFS=$'
	'

# ---- USER OPTIONS ----
DEV=/dev/sda                    # <-- your USB device ONLY
PERSIST_SIZE_GB=8               # size of persistence image
ISO="$PWD/ubuntu-24.04.3-desktop-amd64.iso"
VENTOY="$PWD/ventoy-1.1.07-linux.tar.gz"
TD="$PWD/testdisk-7.2.linux26-x86_64.tar.bz2"

# ---- SAFETY CHECKS ----
# Ensure exFAT tools are present so Ventoy can format the data partition as exFAT (supports >4GB files)
if ! command -v mkfs.exfat >/dev/null 2>&1; then
  echo "exFAT tools not found (mkfs.exfat). On Arch: sudo pacman -S --needed exfatprogs"
  echo "Install them and re-run this script to avoid FAT32 4GB file limit."
  exit 1
fi
[[ -b "$DEV" ]] || { echo "Device $DEV not found"; exit 1; }
[[ -f "$ISO" ]] || { echo "Missing ISO at $ISO"; exit 1; }
[[ -f "$VENTOY" ]] || { echo "Missing Ventoy archive at $VENTOY"; exit 1; }
[[ -f "$TD" ]] || { echo "Missing TestDisk archive at $TD"; exit 1; }

SIZE_GB=$(( $(lsblk -bdno SIZE "$DEV")/1024/1024/1024 ))
(( SIZE_GB >= 32 )) || { echo "Device too small: ${SIZE_GB}GB"; exit 1; }

# Refuse if $DEV is the system disk (backs the mounts /, /boot, /boot/efi)
for mp in / /boot /boot/efi; do
  src=$(findmnt -no SOURCE "$mp" 2>/dev/null || true)
  [[ -n "$src" && $src == /dev/* ]] || continue
  parent=$(lsblk -no PKNAME "$src" 2>/dev/null || true); sysdisk=${parent:+/dev/$parent}
  [[ "$DEV" != "$sysdisk" ]] || { echo "Refusing system disk $DEV"; exit 1; }
done

read -r -p "About to ERASE $DEV only. Type I_UNDERSTAND to continue: " ACK
[[ "$ACK" == I_UNDERSTAND ]]

# ---- CLEANUP TRAPS ----
VT_DIR=$(mktemp -d)
TD_TMP=$(mktemp -d)
cleanup() {
  set +e
  sync
  mountpoint -q /mnt/ventoy && sudo umount /mnt/ventoy || true
  [[ -d /mnt/ventoy ]] && rmdir /mnt/ventoy || true
  [[ -d "$VT_DIR" ]] && rm -rf "$VT_DIR" || true
  [[ -d "$TD_TMP" ]] && rm -rf "$TD_TMP" || true
}
trap cleanup EXIT

# ---- UNMOUNT ANY $DEV PARTITIONS ----
for p in $(lsblk -lnpo NAME,TYPE "$DEV" | awk '$2=="part"{print $1}'); do
  if findmnt -rn -S "$p" >/dev/null 2>&1; then
    sudo umount -q "$p" || true
  fi
done

# ---- INSTALL VENTOY (DESTRUCTIVE ON $DEV) ----
tar -xzf "$VENTOY" -C "$VT_DIR"
VT_EX=$(find "$VT_DIR" -maxdepth 1 -type d -name 'ventoy-*' | head -n1)
[[ -n "$VT_EX" ]] || { echo "Ventoy extract failed"; exit 1; }
yes | sudo bash "$VT_EX/Ventoy2Disk.sh" -I "$DEV"

# ---- MOUNT THE DATA PARTITION (LARGEST PARTITION ON $DEV) ----
sudo udevadm settle || true; sleep 1
DATA_PART=$(lsblk -lnpo NAME,SIZE,TYPE "$DEV" | awk '$3=="part"{print $1, $2}' | sort -k2 -hr | awk 'NR==1{print $1}')
[[ -n "$DATA_PART" ]] || { echo "No data partition on $DEV"; exit 1; }

# If Ventoy created FAT32 (due to missing exFAT tools earlier), reformat to exFAT to support >4GB files
FSTYPE=$(lsblk -no FSTYPE "$DATA_PART" | tr 'A-Z' 'a-z')
if [[ "$FSTYPE" == "vfat" || "$FSTYPE" == "fat32" ]]; then
  echo "Data partition is $FSTYPE; reformatting to exFAT to allow large ISOs..."
  sudo umount "$DATA_PART" 2>/dev/null || true
  sudo mkfs.exfat -n Ventoy "$DATA_PART"
fi

sudo mkdir -p /mnt/ventoy
sudo mount "$DATA_PART" /mnt/ventoy

# ---- COPY ISO ----
sudo mkdir -p /mnt/ventoy/ISO
sudo cp -v "$ISO" /mnt/ventoy/ISO/

# ---- CREATE PERSISTENCE IMAGE ----
IMG="/mnt/ventoy/ISO/ubuntu-persistence-${PERSIST_SIZE_GB}G.img"
sudo dd if=/dev/zero of="$IMG" bs=1M count=$((PERSIST_SIZE_GB*1024)) status=progress conv=fsync
sudo mkfs.ext4 -F -L writable "$IMG"

# ---- WRITE VENTOY PERSISTENCE CONFIG ----
ISO_NAME=$(basename "$ISO")
sudo mkdir -p /mnt/ventoy/ventoy
sudo tee /mnt/ventoy/ventoy/ventoy.json >/dev/null <<'JSON'
{
  "control": [{ "VTOY_DEFAULT_MENU_MODE": "0" }],
  "persistence": [{
    "image": "/ISO/REPLACE_ISO",
    "backend": "/ISO/REPLACE_IMG",
    "autosel": 1
  }]
}
JSON
# Patch placeholders safely (no shell expansion inside heredoc above)
sudo sed -i "s|REPLACE_ISO|${ISO_NAME}|g" /mnt/ventoy/ventoy/ventoy.json
sudo sed -i "s|REPLACE_IMG|ubuntu-persistence-${PERSIST_SIZE_GB}G.img|g" /mnt/ventoy/ventoy/ventoy.json

# ---- ADD TESTDISK TOOLS ----
tar -xjf "$TD" -C "$TD_TMP"
sudo mkdir -p /mnt/ventoy/tools/testdisk
sudo find "$TD_TMP" -type f \( -name testdisk_static -o -name photorec_static \) -print0 \
  | xargs -0 -r sudo cp -t /mnt/ventoy/tools/testdisk/ --

# ---- FINALIZE ----
sync
command -v udisksctl >/dev/null && sudo udisksctl power-off -b "$DEV" || true

echo "Done: $DEV ready (Ventoy + Ubuntu + persistence + TestDisk)"

echo "
Boot steps:
  1) Boot the USB, select ${ISO_NAME}, choose 'Try Ubuntu'.
  2) Run TestDisk: cd /media/ubuntu/*/tools/testdisk && sudo ./testdisk_static"
