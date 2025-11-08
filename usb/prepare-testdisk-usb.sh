#!/usr/bin/env bash
set -euo pipefail

# prepare-testdisk-usb.sh — Create a Ventoy-based Ubuntu USB with persistence and TestDisk.
#
# This script will:
# - Download Ubuntu Desktop ISO, Ventoy, and TestDisk static binaries
# - Install Ventoy to the specified USB device (DESTRUCTIVE to that USB)
# - Create an ext4 persistence image labeled "writable"
# - Copy the ISO and persistence image to the Ventoy data partition
# - Configure Ventoy persistence plugin
# - Copy TestDisk static binaries under /tools/testdisk on the USB
#
# HARD SAFETY RULES
# 1) Never write to any device that is not the explicit USB target.
# 2) Require human confirmation of the target device twice.
# 3) Abort if selected device reports as a system disk or is < 32 GB.
#
# Usage: sudo bash usb/prepare-testdisk-usb.sh

# Remote sources (overridable)
UBUNTU_ISO_URL=${UBUNTU_ISO_URL:-"https://releases.ubuntu.com/24.04/ubuntu-24.04.1-desktop-amd64.iso"}
VENTOY_URL=${VENTOY_URL:-"https://github.com/ventoy/Ventoy/releases/download/v1.0.99/ventoy-1.0.99-linux.tar.gz"}
TESTDISK_URL=${TESTDISK_URL:-"https://www.cgsecurity.org/testdisk-7.2-WIP.linux26-x86_64.tar.bz2"}
WORKDIR=${WORKDIR:-"/tmp/usb_build"}
PERSIST_SIZE_GB=${PERSIST_SIZE_GB:-8}

# Local overrides (skip download if provided)
UBUNTU_ISO_FILE=${UBUNTU_ISO_FILE:-""}
VENTOY_TGZ_FILE=${VENTOY_TGZ_FILE:-""}
TESTDISK_TARBZ2_FILE=${TESTDISK_TARBZ2_FILE:-""}

die() { echo "Error: $*" >&2; exit 1; }

need_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found; please install it and re-run."
}

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    die "Please run as root (sudo)."
  fi
}

confirm_device_twice() {
  echo "[1/10] Listing current block devices" >&2
  lsblk --paths -o PATH,MODEL,SIZE,RM,RO,TYPE,TRAN,MOUNTPOINTS >&2
  echo >&2
  read -r -p "Enter TARGET_DEV for the PNY 64 GB USB (example /dev/sdb): " TARGET_DEV
  [[ -n ${TARGET_DEV:-} ]] || die "No device provided. Abort."
  [[ -b ${TARGET_DEV} ]] || die "Device ${TARGET_DEV} not found. Abort."

  # Size check (>= 32GB)
  local size_gb
  # Use -d to ensure only the whole-disk size is returned (not partitions)
  size_gb=$(lsblk -bdno SIZE "${TARGET_DEV}" | head -n1 | awk '{printf "%.0f\n", $1/1024/1024/1024}')
  if (( size_gb < 32 )); then
    die "Device size ${size_gb} GB is too small (<32GB). Abort."
  fi

  # Refuse system disks (backing /, /boot, or /boot/efi)
  local sys_candidates=()
  local mp src parent sys
  for mp in / /boot /boot/efi; do
    src=$(findmnt -no SOURCE "${mp}" 2>/dev/null || true)
    if [[ -n ${src} && ${src} == /dev/* ]]; then
      parent=$(lsblk -no PKNAME "${src}" 2>/dev/null || true)
      if [[ -n ${parent} ]]; then sys="/dev/${parent}"; else sys="${src}"; fi
      sys_candidates+=("${sys}")
    fi
  done
  # Unique-ify
  if ((${#sys_candidates[@]})); then
    mapfile -t sys_candidates < <(printf "%s\n" "${sys_candidates[@]}" | sort -u)
  fi
  for sd in "${sys_candidates[@]:-}"; do
    if [[ ${TARGET_DEV} == "${sd}" ]]; then
      die "Refusing to operate on probable system disk ${TARGET_DEV}. Abort."
    fi
  done

  echo
  echo "About to ERASE and repartition ${TARGET_DEV}. This will destroy data on that USB only." >&2
  lsblk --paths -o PATH,MODEL,SIZE,RM,RO,TYPE,TRAN "${TARGET_DEV}" >&2 || true
  read -r -p "Type the exact device path again to confirm (${TARGET_DEV}): " RECONFIRM
  [[ ${RECONFIRM} == "${TARGET_DEV}" ]] || die "Device confirmation mismatch. Abort."
  read -r -p "Type I_UNDERSTAND to continue: " ACK
  [[ ${ACK} == I_UNDERSTAND ]] || die "Acknowledgment failed. Abort."
}

mount_data_partition() {
  # Find largest child partition of TARGET_DEV and mount it as Ventoy data
  udevadm settle || true
  sleep 1
  mkdir -p /mnt/ventoy
  local data_part
  data_part=$(lsblk -lnpo NAME,SIZE,TYPE "${TARGET_DEV}" | awk '$3=="part"{print $1" "$2}' | sort -k2 -hr | head -n1 | awk '{print $1}')
  [[ -n ${data_part} ]] || die "Could not determine Ventoy data partition on ${TARGET_DEV}."
  mount "${data_part}" /mnt/ventoy
}

cleanup() {
  sync || true
  if mountpoint -q /mnt/ventoy; then
    umount /mnt/ventoy || true
  fi
  rmdir /mnt/ventoy 2>/dev/null || true
}

main() {
  require_root
  trap cleanup EXIT

  # Tool checks
  for t in curl tar lsblk udevadm sha256sum dd mkfs.ext4 findmnt; do
    need_tool "$t"
  done

  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}"

  confirm_device_twice

  echo "[2/10] Preparing Ubuntu ISO" >&2
  local iso
  if [[ -n ${UBUNTU_ISO_FILE} && -f ${UBUNTU_ISO_FILE} ]]; then
    iso="${UBUNTU_ISO_FILE}"
    echo "Using local ISO: ${iso}" >&2
  else
    iso="${WORKDIR}/$(basename "${UBUNTU_ISO_URL}")"
    echo "Downloading: ${UBUNTU_ISO_URL}" >&2
    curl -fL "${UBUNTU_ISO_URL}" -o "${iso}"
  fi

  echo "[3/10] Preparing Ventoy" >&2
  local ventoy_tgz ventoy_dir
  if [[ -n ${VENTOY_TGZ_FILE} && -f ${VENTOY_TGZ_FILE} ]]; then
    ventoy_tgz="${VENTOY_TGZ_FILE}"
    echo "Using local Ventoy tgz: ${ventoy_tgz}" >&2
  else
    ventoy_tgz="${WORKDIR}/$(basename "${VENTOY_URL}")"
    echo "Downloading: ${VENTOY_URL}" >&2
    curl -fL "${VENTOY_URL}" -o "${ventoy_tgz}"
  fi
  # Extract Ventoy archive and detect directory safely without tripping pipefail
  set +o pipefail
  ventoy_dir=$(tar -tzf "${ventoy_tgz}" 2>/dev/null | head -n1 | sed -E 's#^\./##; s#/.*$##')
  set -o pipefail
  tar -xzf "${ventoy_tgz}"
  [[ -n ${ventoy_dir} && -d ${ventoy_dir} ]] || die "Failed to extract Ventoy archive."

  echo "[4/10] Installing Ventoy to USB" >&2
  "${ventoy_dir}/Ventoy2Disk.sh" -I "${TARGET_DEV}" <<<'Y'

  echo "[5/10] Mounting Ventoy data partition" >&2
  mount_data_partition

  echo "[6/10] Copying Ubuntu ISO to Ventoy" >&2
  mkdir -p /mnt/ventoy/ISO
  cp -v "${iso}" /mnt/ventoy/ISO/

  echo "[7/10] Creating Ubuntu persistence image (${PERSIST_SIZE_GB} GB)" >&2
  local persist_img
  persist_img="/mnt/ventoy/ISO/ubuntu-persistence-${PERSIST_SIZE_GB}G.img"
  dd if=/dev/zero of="${persist_img}" bs=1M count=$((PERSIST_SIZE_GB*1024)) status=progress conv=fsync
  mkfs.ext4 -F -L writable "${persist_img}"

  echo "[8/10] Writing Ventoy persistence config" >&2
  local iso_name
  iso_name=$(basename "${iso}")
  mkdir -p /mnt/ventoy/ventoy
  cat > /mnt/ventoy/ventoy/ventoy.json <<EOF
{
  "control": [
    { "VTOY_DEFAULT_MENU_MODE": "0" }
  ],
  "persistence": [
    {
      "image": "/ISO/${iso_name}",
      "backend": "/ISO/ubuntu-persistence-${PERSIST_SIZE_GB}G.img",
      "autosel": 1
    }
  ]
}
EOF

  echo "[9/10] Preparing TestDisk static build" >&2
  local td_tar td_dir
  if [[ -n ${TESTDISK_TARBZ2_FILE} && -f ${TESTDISK_TARBZ2_FILE} ]]; then
    td_tar="${TESTDISK_TARBZ2_FILE}"
    echo "Using local TestDisk tarball: ${td_tar}" >&2
  else
    td_tar="${WORKDIR}/$(basename "${TESTDISK_URL}")"
    echo "Downloading: ${TESTDISK_URL}" >&2
    curl -fL "${TESTDISK_URL}" -o "${td_tar}"
  fi
  tar -xjf "${td_tar}"
  td_dir=$(find "${WORKDIR}" -maxdepth 1 -type d -name "testdisk-*" | head -n1 || true)
  [[ -n ${td_dir} && -d ${td_dir} ]] || die "Failed to extract TestDisk archive."
  mkdir -p /mnt/ventoy/tools/testdisk
  cp -v "${td_dir}"/* /mnt/ventoy/tools/testdisk/

  echo "[10/10] Sync and unmount" >&2
  sync
  umount /mnt/ventoy || true
  rmdir /mnt/ventoy 2>/dev/null || true

  # Optional: power off the USB device if udisksctl is available
  if command -v udisksctl >/dev/null 2>&1; then
    udisksctl power-off -b "${TARGET_DEV}" >/dev/null 2>&1 || true
  fi

  echo "Done. USB is ready." >&2
  echo >&2
  echo "Boot steps:" >&2
  echo "1) Boot target PC from this USB" >&2
  echo "2) In Ventoy menu, select ${iso_name} (persistence auto-wired)" >&2
  echo "3) Choose Try Ubuntu" >&2
  echo "4) TestDisk at /media/ubuntu/VENTOY/tools/testdisk (path may vary)." >&2
  echo "   Run: ./testdisk_static or ./photorec_static" >&2
}

main "$@"
