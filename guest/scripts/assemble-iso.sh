#!/bin/bash
#
# assemble-iso.sh: produces a BIOS-bootable El Torito ISO9660 CD-ROM.
# Takes a workdir containing vmlinuz, initramfs.img, and the cmdline
# template, emits an ISO that SeaBIOS (Proxmox i440fx default) can
# boot directly.
#
# amd64 only: isolinux is x86 firmware, and Alpine's syslinux package
# only ships on x86 repos. The justfile guards this before the build
# stage is even invoked.
#
# Usage: assemble-iso.sh <workdir> <output-iso>
#
# Inputs in <workdir>:
#   vmlinuz         kernel
#   initramfs.img   xz cpio initramfs produced by init-mkinitramfs.sh
#   cmdline         kernel cmdline template with literal ${CONSOLE}
#
set -euo pipefail

WORKDIR="${1:?usage: $0 <workdir> <output-iso>}"
OUT="${2:?usage: $0 <workdir> <output-iso>}"

# Validate input files exist
for f in "${WORKDIR}/vmlinuz" "${WORKDIR}/initramfs.img" "${WORKDIR}/cmdline"; do
    [[ -f "${f}" ]] || { echo "ERROR: missing ${f}" >&2; exit 1; }
done

# Validate syslinux files exist
for f in /usr/share/syslinux/isolinux.bin /usr/share/syslinux/ldlinux.c32; do
    [[ -f "${f}" ]] || { echo "ERROR: missing syslinux file: ${f}" >&2; exit 1; }
done

CONSOLE=ttyS0
CMDLINE="$(sed "s|\${CONSOLE}|${CONSOLE}|g" "${WORKDIR}/cmdline")"

ISO_ROOT="${WORKDIR}/iso-root"
rm -rf "${ISO_ROOT}"
mkdir -p "${ISO_ROOT}/isolinux"

cp /usr/share/syslinux/isolinux.bin "${ISO_ROOT}/isolinux/isolinux.bin"
cp /usr/share/syslinux/ldlinux.c32  "${ISO_ROOT}/isolinux/ldlinux.c32"
cp "${WORKDIR}/vmlinuz"       "${ISO_ROOT}/vmlinuz"
cp "${WORKDIR}/initramfs.img" "${ISO_ROOT}/initramfs.img"

cat > "${ISO_ROOT}/isolinux/isolinux.cfg" <<EOF
default bingo
prompt 0
timeout 0

label bingo
    kernel /vmlinuz
    append initrd=/initramfs.img ${CMDLINE}
EOF

mkdir -p "$(dirname "${OUT}")"

echo "==> Building ISO at ${OUT}..."
xorriso -as mkisofs \
    -V BINGO \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -o "${OUT}" \
    "${ISO_ROOT}"

echo "==> Build complete: $(du -h "${OUT}" | cut -f1)"
