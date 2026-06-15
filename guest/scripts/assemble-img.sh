#!/bin/bash
#
# assemble-img.sh: produces a minimal bootable disk image. Takes a
# Unified Kernel Image (UKI) and emits a GPT+FAT disk with a single
# file on the ESP at /EFI/BOOT/BOOT{X64,AA64}.EFI. UEFI firmware
# loads that file directly; there is no separate bootloader, kernel,
# or initramfs on the ESP.
#
# Usage: assemble-img.sh <uki-path> <output-img>
#
set -euo pipefail

UKI="${1:?usage: $0 <uki-path> <output-img>}"
OUT="${2:?usage: $0 <uki-path> <output-img>}"

# Validate input file exists
[[ -f "${UKI}" ]] || { echo "ERROR: UKI file not found: ${UKI}" >&2; exit 1; }

case "$(uname -m)" in
    x86_64)  efi_binary=BOOTX64.EFI ;;
    aarch64) efi_binary=BOOTAA64.EFI ;;
    *) echo "ERROR: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

uki_kb=$(du -k "${UKI}" | cut -f1)
# +2 MB slack covers FAT metadata; +1 MB covers GPT + 1 MiB partition
# alignment.
esp_size_mb=$((uki_kb / 1024 + 2))
img_size_mb=$((esp_size_mb + 1))

mkdir -p "$(dirname "${OUT}")"

echo "==> Creating ${img_size_mb}MB disk image (ESP=${esp_size_mb}MB)..."
truncate -s "${img_size_mb}M" "${OUT}"

parted -s "${OUT}" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 100% \
    set 1 esp on

esp_img="$(mktemp -u --suffix=.esp)"
truncate -s "${esp_size_mb}M" "${esp_img}"
mkfs.fat -n ESP "${esp_img}"

export MTOOLS_SKIP_CHECK=1
mmd   -i "${esp_img}" ::/EFI ::/EFI/BOOT
mcopy -i "${esp_img}" "${UKI}" "::/EFI/BOOT/${efi_binary}"

# Partition 1 starts at 1 MiB per `parted ... 1MiB 100%`.
dd if="${esp_img}" of="${OUT}" \
    bs=1M seek=1 count="${esp_size_mb}" \
    conv=notrunc status=none

rm -f "${esp_img}"

echo "==> Build complete: $(du -h "${OUT}" | cut -f1)"
