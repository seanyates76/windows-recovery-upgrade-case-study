# Repository Guidelines

This repo documents a preservation‑first Windows 11 install and a Linux USB creation script. Use the guidance below to keep contributions consistent and safe.

## Project Structure & Module Organization
- `usb/prepare-usb.sh` — Bash script to create a UEFI‑bootable Win11 USB (FAT32 + WIM split).
- `usb/prepare-ventoy-persistent-usb.sh` — Ventoy‑based Ubuntu USB with persistence + TestDisk (from local files).
- `winsetup/` — Step‑by‑step install notes (e.g., driver loading).
- `README.md` — Overview and workflow; start here.
- `troubleshooting.md`, `session-notes.md` — Reference notes and flows.

## Build, Test, and Development Commands
- Dependencies (script): `rsync`, `parted`, `mkfs.fat`, `wimlib-imagex`.
 - Ventoy persistent USB: `mkfs.exfat` from `exfatprogs` (recommended), `mkfs.ntfs` from `ntfs-3g` (optional fallback).
- Safe loopback test (no real USB):
  - `dd if=/dev/zero of=/tmp/usb.img bs=1M count=64 && sudo losetup -fP /tmp/usb.img`
  - `sudo bash usb/prepare-usb.sh /dev/loop0 /path/to/Win11.iso WIN11`
  - `sudo losetup -d /dev/loop0`
- Real run (DANGEROUS): confirm device first — `lsblk --paths` → `sudo bash usb/prepare-usb.sh /dev/sdX /path/to/Win11.iso [LABEL]`.

## Coding Style & Naming Conventions
- Markdown: Title Case headings, short paragraphs, numbered steps for procedures, code blocks with triple backticks, commands/paths in backticks (e.g., `U:` or `C:\\Windows.old`).
- Bash: `set -euo pipefail`, 2‑space indent, check tools with `command -v`, explicit errors to `stderr`, kebab‑case filenames.
- Formatting tools (recommended): `shellcheck`, `shfmt`, `markdownlint` (if available).

## Testing Guidelines
- Script: `shellcheck usb/prepare-usb.sh` and `shfmt -d usb/prepare-usb.sh` before PR.
- Functional: prefer loopback test above; never target an unknown `/dev/sdX`. If testing on hardware, photograph/attach `lsblk` output showing the intended device.
- Docs: ensure commands copy/paste cleanly and reflect actual prompts/output.

## Commit & Pull Request Guidelines
- Commits: imperative mood; concise subject (<72 chars). Prefer Conventional‑style types: `docs:`, `feat:`, `fix:`, `chore:`.
- PRs must include: purpose, what changed, screenshots or terminal logs for procedures, test plan (loopback/device verification), and any risks.

## Safety & Configuration Tips
- Always verify the target device with `lsblk --paths`; unplug other external disks when possible.
- Run destructive actions only with explicit confirmation; the script prompts — read it carefully.
- BIOS/UEFI settings: UEFI mode, CSM off, AHCI (RAID only if intended); align docs with these defaults.
 - Large ISOs (>4GB): ensure the Ventoy data partition is exFAT or NTFS; FAT32 will fail to copy.
