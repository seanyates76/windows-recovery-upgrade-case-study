# Case Study: Windows 10 Activation Failure → Windows 11 Recovery & Upgrade

*This repository documents a professional data-preserving repair and OS upgrade case study, shared for educational and portfolio purposes. Client data and identifying details are omitted for privacy.*

---

## Summary

A client’s Windows 10 Pro system refused activation despite a valid license key. Investigation revealed severe corruption of activation, update, and boot services following a failed Windows update. With Windows 10 officially out of support, I proposed a clean upgrade to Windows 11. The process evolved into a full EFI, partition, and activation rebuild—recovering the client’s data and successfully upgrading to a genuine Windows 11 Pro installation.

---

## Context

* **Initial report:** Windows 10 Pro would not activate.
* **System state:** Bootable, but key utilities and services were missing; activation and update services failed to start.
* **Root cause:** File system corruption from a botched Windows 10 update.
* **Goal:** Recover data, restore boot capability, and migrate the client to a supported Windows 11 build.

---

## Tools & Environment

* **Hardware:** High-end gaming PC (Windows 10 Pro → Windows 11 Pro).
* **Utilities:** TestDisk, Rufus, Ventoy, Ubuntu Live, `bcdboot`, `diskpart`, `sfc`, `DISM`, and Windows Setup environment.
* **Environment:** Linux workstation used for early recovery, later replaced with a Windows environment for the final media build.
* **Automation:** Limited command assistance for scripting and documentation.

---

## Diagnostic Process

1. Verified Windows 10 activation failure through Settings and `slmgr`.
2. Confirmed the product key matched the Windows 10 Pro edition.
3. Ran `sfc /scannow` and `DISM /RestoreHealth`; both found corruption.
4. Consulted the previous owner, who confirmed issues began after an incomplete update.
5. Determined the activation and update services were damaged beyond repair, justifying a full migration to Windows 11.

---

## Installation Media Preparation

* **Attempt 1 (Ventoy + WoeUSB):** Created Windows 11 installation media on Linux, which introduced bootloader corruption and driver recognition issues.
* **Command Context Error:** During diagnostics, a misunderstood automation instruction triggered `diskpart clean` on the main drive, erasing the partition table.
* **Immediate Response:** Informed the client, confirmed that only non-critical data was at risk, and began recovery.

---

## Boot Repair and System Recovery

After the accidental wipe, the objective was to reconstruct the drive partitions, recover data, and restore boot functionality before performing an in-place Windows 11 upgrade.

### Partition Recovery

Used **TestDisk** from an Ubuntu Live environment to rebuild the partition table:

* Detected three partitions: **NTFS (System)**, **Recovery**, and **EFI (FAT32, 100MB)**.
* Rewrote the partition table successfully.
* Attempted mounting for backup, but NTFS returned *“volume in inconsistent state”*, preventing file copying.

*Result: A traditional backup was not possible, but partition integrity was successfully restored.*

### Persistent Environment

Built a Ventoy USB with an Ubuntu ISO and 8 GB persistence file to enable logging and safe, repeatable testing sessions. This allowed all recovery steps to be documented while preserving changes between boots.

### EFI Reconstruction

Once partitions were restored, a new Windows 11 USB was built using **Rufus** in GPT/UEFI mode.
From the Windows installer’s **Shift + F10** command prompt:

1. Identified the EFI volume and reformatted it as FAT32.
2. Rebuilt the bootloader with `bcdboot`.
3. Verified successful output message: *“Boot files successfully created.”*

The system then booted normally back into the recovered Windows 10 installation with data intact.

---

## Recovery & Rebuild

Post-recovery validation revealed missing or corrupted system components:

| Subsystem              | Symptoms                                  | Cause                                                                    |
| ---------------------- | ----------------------------------------- | ------------------------------------------------------------------------ |
| Activation & Licensing | `slmgr` errors `0xC004F002`, `0xC0000022` | Broken `sppsvc` service and missing DLLs (`sppcommdlg.dll`, `slwga.dll`) |
| Windows Update         | Stuck at *“Checking for updates 46%”*     | Damaged servicing stack                                                  |
| Boot Utilities         | Initial `bcdboot` errors                  | Malformed EFI structure (since corrected)                                |

Because Windows 10 could not self-repair through Update or SFC, an **in-place Windows 11 upgrade** was initiated to rebuild these frameworks automatically while preserving files and apps.

---

## Activation & Verification

1. Windows 11 installation completed successfully after overnight updating.
2. Activation initially failed but succeeded instantly when re-entering the original Windows 10 Pro key—validated through Microsoft’s free upgrade entitlement.
3. Verified system integrity and update functionality:

   ```cmd
   sfc /scannow
   DISM /Online /Cleanup-Image /CheckHealth
   ```

All checks passed with no integrity violations.

---

## Results

* Fully activated, genuine Windows 11 Pro installation
* Verified system and component-store integrity
* Restored Windows Update and driver functionality
* Successful recovery following partition wipe and EFI rebuild
* Client upgraded from unsupported Windows 10 to a secure, modern OS

---

## Lessons & Reflections

This case underscored how essential context is when working with automated tools. The diskpart clean command was issued without destructive intent—an instruction executed accurately but without full awareness of scope. It taught me that precision isn’t only about syntax, it’s about shared understanding. I now take greater care to frame objectives clearly, validate assumptions early, and confirm every target before acting. Good troubleshooting isn’t just about technical skill; it’s about communication and intent. Whether with a client, a teammate, or an automated assistant, clarity matters more than speed, and that awareness has made me more deliberate, more careful, and ultimately more effective in how I work.

---

## Supporting Documentation

* [Troubleshooting log](./docs/troubleshooting.md)
* [TestDisk media build notes](./docs/tools/testdisk-media.md)
* [Session notes & timeline](./docs/notes/session-notes.md)
* [Automation context notes](./AGENTS.md)

---

## Repository Structure

| File                                 | Purpose                                                 |
| ------------------------------------ | ------------------------------------------------------- |
| `README.md`                          | Case study summary and results                          |
| `docs/troubleshooting.md`            | Logs and command outputs                                |
| `docs/tools/testdisk-media.md`       | Recovery and build instructions                         |
| `docs/notes/session-notes.md`        | Chronological notes and process record                  |
| `docs/windows/driver-loading.md`     | Windows driver loading / setup notes                    |
| `scripts/usb/`                       | USB preparation scripts (Win11, TestDisk, Ventoy pers.) |
| `AGENTS.md`                          | Automation context and command documentation            |


---

## Technical Appendix (for Reviewers)

<details>
<summary>Partition Recovery (Ubuntu Live + TestDisk)</summary>

```bash
# Identify drives
sudo fdisk -l

# Install TestDisk
sudo apt install testdisk

# Launch recovery
sudo testdisk_static
```

* Selected `/dev/sda` (the affected SSD) and performed a deep search for NTFS and FAT32 volumes.
* Located three partitions: NTFS (System), Recovery, EFI (FAT32 100 MB).
* Rewrote the partition table to disk and marked the NTFS partition as bootable.
* Mount attempts failed due to inconsistent NTFS state, confirming the need for later OS-level repair.

</details>

<details>
<summary>Persistent Environment Build (Ventoy + Ubuntu ISO)</summary>

```bash
sudo bash Ventoy2Disk.sh -I /dev/sdb
sudo mount /dev/sdb1 /mnt/ventoy
sudo cp ubuntu-24.04.3-desktop-amd64.iso /mnt/ventoy/ISO/
```

Created an 8 GB persistence image and linked it in `ventoy.json`:

```json
{
  "control_ventoy": {
    "VTOY_DEFAULT_IMAGE": "/ISO/ubuntu-24.04.3-desktop-amd64.iso",
    "VTOY_PERSISTENT_PART": "/ventoy/persistence.img"
  }
}
```

This setup enabled live session logging and iterative testing without re-creating the USB each time.

</details>

<details>
<summary>EFI Reconstruction (Windows 11 Installer → Shift + F10)</summary>

```cmd
diskpart
list vol
sel vol 2
format fs=fat32 quick label=System override
assign letter=S
exit
bcdboot C:\Windows /s S: /f UEFI
```

* Reformatted the EFI partition to ensure a writable FAT32 structure.
* Rebuilt boot files with `bcdboot`.
* Verified message: *“Boot files successfully created.”*
* Rebooted and confirmed entry into Windows Boot Manager.

</details>

<details>
<summary>System Verification and Activation (Windows 11)</summary>

```powershell
# Verify activation
slmgr /xpr

# Check service status
Get-Service wuauserv, bits, cryptsvc | Select Name, Status

# System integrity
sfc /scannow
DISM /Online /Cleanup-Image /CheckHealth
```

Confirmed Windows 11 Pro activation under a digital license, verified update services, and ensured full system integrity.

</details>

---

(c) 2025 Sean Yates — Educational and portfolio documentation only. Client data and identifying details omitted for privacy.
