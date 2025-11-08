# Windows Setup — Loading Storage Drivers (F6)

Most systems in AHCI mode do not need extra drivers to install Windows 11. Only load a driver if Setup cannot see your storage due to a non‑standard controller (e.g., RAID, ASMedia/Marvell, add‑in cards).

## 1) Make the USB visible (assign a letter)
In Windows Setup, press Shift+F10 and run:

```
diskpart
list volume
select volume <USB_FAT32_vol#>   # ~59–60GB, may say Hidden
attributes volume clear hidden
assign letter=U
exit
U:
dir
```

You should see `boot`, `efi`, `sources`, `setup.exe` on U:\. If you only see an `EFI` folder, you assigned the small internal EFI partition — remove the letter and assign U: to the 60GB USB instead:

```
diskpart
list volume
select volume <tiny_efi_vol#>
remove letter=U
select volume <usb_fat32_vol#>
assign letter=U
exit
```

Note: X:\ is WinPE (RAM disk). It’s normal and not your USB.

## 2) Load the driver
In the “Load driver” dialog:
- Browse to `U:\Drivers\<YourDriverFolder>` (you must copy/extract the driver files there in advance).
- Check “Include subfolders”.
- Select the storage controller driver when shown.

AMD RAID example (only if RAID/NVMe RAID enabled):
- Files look like: `rcbottom.inf`, `rccfg.inf`, `rcraid.inf`, and for NVMe RAID: `rnvme.inf`.

ASMedia/Marvell SATA example:
- Use the board vendor’s F6/Preinstall package for the exact controller.

## 3) If SSD still doesn’t appear (preserve data)
Preservation‑first checks:
- BIOS: UEFI mode, CSM disabled, SATA = AHCI, NVMe RAID disabled.
- Cabling/slot: reseat the drive or try another M.2/SATA port.
- If the system uses RAID or a 3rd‑party controller, load that F6 driver as above.

Do NOT run `clean` or format if keeping files.
- If partitions look missing/corrupt, use TestDisk to rebuild the GPT or copy files to an external drive, then proceed with the Windows.old method.
