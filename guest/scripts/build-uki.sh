#!/bin/bash
#
# build-uki.sh: packs kernel + initramfs + cmdline into a Unified
# Kernel Image - a single PE binary that UEFI firmware loads directly
# from /EFI/BOOT/BOOTAA64.EFI. Runs inside the ukibuilder stage.
#
# Input files:
#   /uki/vmlinuz        kernel
#   /uki/initramfs.img  initramfs produced by init-mkinitramfs.sh
#   /uki/cmdline        cmdline template with literal ${CONSOLE}
#
# Output:
#   /uki/BOOT.EFI
#
set -euo pipefail

# Validate input files exist
for f in /uki/vmlinuz /uki/initramfs.img /uki/cmdline; do
    [[ -f "${f}" ]] || {
        echo "ERROR: missing ${f}" >&2
        exit 1
    }
done

# arm64 QEMU virt exposes a PL011 UART as ttyAMA0. Under Apple's
# Virtualization.framework the guest instead gets a virtio-console (hvc0),
# which the cmdline template appends directly.
CONSOLE=ttyAMA0

CMDLINE="$(sed "s|\${CONSOLE}|${CONSOLE}|g" /uki/cmdline)"

ukify build \
    --linux=/uki/vmlinuz \
    --initrd=/uki/initramfs.img \
    --cmdline="${CMDLINE}" \
    --output=/uki/BOOT.EFI
