# Session Notes —  windows-recovery-upgrade-case-study


Context summary
- Goal: Prepare a Windows 11 installer USB and install on a gaming PC.
- USB: 59.8GB flash drive, created on Linux with GPT + FAT32. ISO contents copied; `install.wim` (6.4GB) split to 3.8GB SWM chunks.
- BIOS storage mode: User reports AHCI (no RAID). In AHCI, Windows 11 should see the SSD without extra drivers.

Key commands executed (Linux)
- Partitioned/Formatted USB:
  - `parted` → GPT + primary FAT32 1MiB‑100%, flags `esp` and `boot`
  - `mkfs.fat -F32 -n WIN11 /dev/sda1`
- Copied ISO contents, excluding `sources/install.wim`:
  - `rsync -rltD --delete --no-perms --no-owner --no-group --exclude=/sources/install.wim /mnt/iso/ /mnt/winusb/`
- Split WIM:
  - `wimlib-imagex split /mnt/iso/sources/install.wim /mnt/winusb/sources/install.swm 3800`

Windows Setup troubleshooting performed
- Clarified that X:\ is WinPE RAM drive; USB may have no drive letter by default.
- Assigned letter to USB via `diskpart` → `list volume` → `attributes volume clear hidden` → `assign letter=U`.
- Cleaned SSD using `diskpart clean` and `convert gpt` to make it selectable in Setup (this intentionally removed prior partitions/data).

Tips recorded
- “Load driver” only needed for RAID (AMD RAIDXpert2) or third‑party controllers (ASMedia/Marvell/PCIe RAID).
- For AHCI installs, cleaning and converting the SSD to GPT normally resolves detection issues.

Next steps
- In Setup, select the unallocated SSD and click Next to install Windows.
- After first boot: install chipset + GPU drivers, run Windows Update, activate.

