# Troubleshooting — Disk Not Showing in Windows Setup

Use this flow to quickly resolve missing disks during Windows 11 setup.

## 1) Firmware sanity
- Boot mode: UEFI (disable CSM/Legacy).
- Storage mode: AHCI (unless you explicitly use RAID). Ensure NVMe RAID is Disabled.
- Confirm the drive appears in BIOS/UEFI. If not, reseat or try another slot/port; update BIOS.

## 2) Make the USB visible (assign letter)
In Setup (Shift+F10):
```
diskpart
list volume
select volume <USB FAT32 ~59–60GB>
attributes volume clear hidden
assign letter=U
exit
U:
dir
```
If `dir` shows only `EFI`, you assigned the tiny internal EFI partition — remove and reassign to the 60GB USB.

## 3) Preserve data (do NOT clean)
If the SSD isn’t selectable or partitions look odd, avoid destructive steps.

Options that keep files:
- If Windows still boots: run `setup.exe` from the USB inside Windows → choose “Keep personal files and apps”.
- If Windows doesn’t boot: use the Windows.old method — in Setup choose Custom, select the existing Windows partition (no delete/format). Windows will place the old install in `C:\Windows.old`.
- If partitions seem missing/corrupt: use TestDisk to rebuild the partition table or to copy files to an external drive before proceeding.
  - See `testdisk-media.md` to create a persistent Ubuntu USB with TestDisk.

## 4) Drivers (only when needed)
- Chipset AHCI/NVMe: Windows 11 includes drivers.
- RAID (AMD RAIDXpert2): Use AMD “RAID Driver (SATA, NVMe RAID) – Preinstall (F6)”. Load `rcbottom.inf`, `rccfg.inf`, `rcraid.inf` (+ `rnvme.inf` for NVMe arrays).
- Third‑party SATA/NVMe controllers (ASMedia/Marvell/PCIe cards): use the vendor’s F6 package.

Copy extracted `.inf/.sys/.cat` files to `U:\Drivers\...` and use “Load driver” → Include subfolders.

## 5) USB integrity
- Use a rear USB 2.0/3.0 port directly on the motherboard (avoid hubs/front panel).
- If creation is suspect, recreate the USB (Linux script in `usb/prepare-usb.sh` or Rufus on Windows). Ensure FAT32 + WIM split for UEFI compatibility.

## 6) Misc
- X:\ is WinPE RAM disk — expected. Don’t browse X:\ for drivers.
- If BitLocker/previous OS is present, the `clean` step removes those partitions; that’s expected for a fresh install.
