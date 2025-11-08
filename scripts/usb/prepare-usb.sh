#!/usr/bin/env bash
set -euo pipefail

# prepare-usb.sh — Create a UEFI Windows 11 USB with FAT32 + WIM split.
# Usage: sudo ./prepare-usb.sh /dev/sdX /path/to/Win11.iso [LABEL]

DEV=${1:-}
ISO=${2:-}
LABEL=${3:-WIN11}

if [[ -z ${DEV} || -z ${ISO} ]]; then
  echo "Usage: sudo $0 /dev/sdX /path/to/Win11.iso [LABEL]" >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

if [[ ! -b ${DEV} ]]; then
  echo "Device not found: ${DEV}" >&2
  exit 1
fi

if [[ ! -f ${ISO} ]]; then
  echo "ISO not found: ${ISO}" >&2
  exit 1
fi

echo "WARNING: This will erase ${DEV}. Continue? [y/N]"
read -r ans
[[ ${ans,,} == y || ${ans,,} == yes ]] || exit 1

umount -q ${DEV}?* 2>/dev/null || true

echo "[1/6] Wiping signatures..."
wipefs -a ${DEV}

echo "[2/6] Partitioning GPT + FAT32..."
parted -s ${DEV} mklabel gpt
parted -s ${DEV} mkpart primary fat32 1MiB 100%
parted -s ${DEV} set 1 esp on
parted -s ${DEV} set 1 boot on
partprobe ${DEV}

echo "[3/6] Formatting FAT32..."
mkfs.fat -F32 -n "${LABEL}" ${DEV}1

echo "[4/6] Mounting..."
mkdir -p /mnt/winusb /mnt/iso
mount ${DEV}1 /mnt/winusb
mount -o ro,loop "${ISO}" /mnt/iso

echo "[5/6] Copying files (excluding large WIM)..."
if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync not found; install rsync and re-run." >&2
  exit 1
fi

rsync -rltD --delete --no-perms --no-owner --no-group \
  --exclude=/sources/install.wim \
  /mnt/iso/ /mnt/winusb/

echo "[6/6] Handling WIM/ESD..."
mkdir -p /mnt/winusb/sources
if [[ -f /mnt/iso/sources/install.wim ]]; then
  if ! command -v wimlib-imagex >/dev/null 2>&1; then
    echo "wimlib-imagex not found; install wimlib and re-run." >&2
    exit 1
  fi
  echo "Splitting install.wim to 3.8GB SWM parts..."
  wimlib-imagex split /mnt/iso/sources/install.wim /mnt/winusb/sources/install.swm 3800
elif [[ -f /mnt/iso/sources/install.esd ]]; then
  echo "Copying install.esd..."
  rsync -rltD --no-perms --no-owner --no-group /mnt/iso/sources/install.esd /mnt/winusb/sources/
else
  echo "Warning: No install.wim or install.esd found in ISO." >&2
fi

sync
umount /mnt/iso || true
sync
umount /mnt/winusb || true

echo "Done. USB ${DEV} is ready for UEFI boot."

