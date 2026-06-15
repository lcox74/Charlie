#!/bin/bash
#
# build-uki.sh: packs kernel + initramfs + cmdline into a Unified
# Kernel Image - a single PE binary that UEFI firmware loads directly
# from /EFI/BOOT/BOOT{X64,AA64}.EFI. Runs inside the ukibuilder stage.
#
# Inputs (env vars):
#   TARGETARCH       amd64 or arm64; selects the serial console
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

# Validate required environment variable
: "${TARGETARCH:?ERROR: TARGETARCH is not set}"

# Validate input files exist
for f in /uki/vmlinuz /uki/initramfs.img /uki/cmdline; do
    [[ -f "${f}" ]] || { echo "ERROR: missing ${f}" >&2; exit 1; }
done

case "${TARGETARCH}" in
    amd64) CONSOLE=ttyS0 ;;
    arm64) CONSOLE=ttyAMA0 ;;
    *)
        echo "unsupported arch ${TARGETARCH}" >&2
        exit 1
        ;;
esac

CMDLINE="$(sed "s|\${CONSOLE}|${CONSOLE}|g" /uki/cmdline)"

ukify build \
    --linux=/uki/vmlinuz \
    --initrd=/uki/initramfs.img \
    --cmdline="${CMDLINE}" \
    --output=/uki/BOOT.EFI

