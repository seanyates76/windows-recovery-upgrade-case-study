# Ubuntu Persistent USB With TestDisk

This procedure creates a Ventoy-based Ubuntu Desktop USB with persistence and TestDisk static binaries. It follows a strict safety model to avoid writing to the wrong disk.

## Requirements
1) Linux host with `bash`, `tar`, `lsblk`, `udevadm`, `dd`, `mkfs.ext4`, and exFAT tools (`mkfs.exfat` from `exfatprogs`)
2) Hardware: PNY 64 GB USB 3.2 stick (or any ≥32 GB USB drive)
3) Local files in repo root (preferred):
   - `ubuntu-24.04.3-desktop-amd64.iso`
   - `ventoy-1.1.07-linux.tar.gz`
   - `testdisk-7.2.linux26-x86_64.tar.bz2`
   (Alternatively, use the downloader script or fetch these from the official sites.)

## Safety Rules
1) Never write to any device that is not the explicit USB target.
2) Confirm the target device twice (exact path + typed acknowledgment).
3) Abort if the device size is < 32 GB or if it appears to be a system disk.

## Script
Use the script in `usb/prepare-ventoy-persistent-usb.sh` (uses your local ISO + packages).

```
sudo bash usb/prepare-ventoy-persistent-usb.sh /dev/sdX
```

You will be shown `lsblk --paths` output and asked to re‑confirm the exact device and type `I_UNDERSTAND`. The script:
- Installs Ventoy onto the target USB (destructive to that USB)
- Creates an `ext4` persistence image labeled `writable`
- Copies your ISO + persistence image to the USB
- Writes `ventoy.json` to auto-wire persistence
- Adds TestDisk binaries under `/tools/testdisk` on the USB
- Syncs and safely unmounts

Notes:
- Large ISOs (>4GB) need the Ventoy data partition to be exFAT/NTFS. Install exFAT tools (e.g., `exfatprogs`) before running. The script will reformat the data partition to exFAT if it detects FAT32.
- You can set environment overrides: `UBUNTU_ISO_FILE`, `VENTOY_TGZ_FILE`, `TESTDISK_TARBZ2_FILE`, and `PERSIST_SIZE_GB`.

## Verification
After the build, verify contents and space:
```
DATA=$(lsblk -lnpo NAME,SIZE,TYPE /dev/sdX | awk '$3=="part"{print $1" "$2}' | sort -k2 -hr | awk 'NR==1{print $1}')
sudo mkdir -p /mnt/ventoy && sudo mount "$DATA" /mnt/ventoy
ls -lh /mnt/ventoy/ISO
sed -n '1,120p' /mnt/ventoy/ventoy/ventoy.json
ls -lh /mnt/ventoy/tools/testdisk
df -h /mnt/ventoy
```

## Troubleshooting
- Error: `cp: ... File too large` when copying the ISO
  - Cause: Data partition is FAT32 (4GB file limit). Solution: format as exFAT (preferred) or NTFS.
  - Commands (example):
    ```
    sudo umount -l /mnt/ventoy 2>/dev/null || true
    sudo mkfs.exfat -n Ventoy /dev/sdX1
    sudo mount /dev/sdX1 /mnt/ventoy
    ```
- If persistence image creation fails, ensure there is ≥9–10GB free on the USB and try again.

## Safe Eject
```
sync && sudo umount /mnt/ventoy && rmdir /mnt/ventoy || true
command -v udisksctl >/dev/null && sudo udisksctl power-off -b /dev/sdX || true
```

## On-Site Minimal Workflow
1) Boot the target PC from the USB
2) In the Ventoy menu, select the Ubuntu Desktop ISO (persistence is auto-configured)
3) Choose Try Ubuntu
4) Open Terminal and run TestDisk static:
   ```
   cd /media/ubuntu/*/tools/testdisk
   sudo ./testdisk_static
   ```
5) Analyse → Quick Search → if partitions are found, write the table
6) Mount recovered volume and copy user data to your external backup drive

## Manual Option
If you prefer not to use the script, you can follow the command block in the repository root README “Ubuntu Persistent USB (Quick Start)” section to perform the steps manually.

## Notes
- Ventoy keeps the stick reusable. You can drop in other ISOs later.
- The persistence image is labeled `writable` for Ubuntu `casper`.
- TestDisk static binaries run without installing packages or network.
