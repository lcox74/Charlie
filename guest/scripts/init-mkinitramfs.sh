#!/bin/bash
#
# init-mkinitramfs.sh: wraps the static Go init binary into a newc
# cpio archive, xz-compressed. Runs inside the ukibuilder and
# isobuilder Docker stages.
#
# Usage: init-mkinitramfs.sh <workdir>
#
# Inputs in <workdir>:
#   init-bin          the statically-linked Go init
#
# Output in <workdir>:
#   initramfs.img     newc+xz cpio archive with /init and the
#                     minimal mountpoint dirs
#
set -euo pipefail

WORKDIR="${1:?usage: $0 <workdir>}"

# Validate input file exists
[[ -f "${WORKDIR}/init-bin" ]] || { echo "ERROR: missing ${WORKDIR}/init-bin" >&2; exit 1; }

STAGE="${WORKDIR}/rootfs"

mkdir -p "${STAGE}/dev" "${STAGE}/proc" "${STAGE}/sys" \
         "${STAGE}/etc" "${STAGE}/tmp" "${STAGE}/run"

cp "${WORKDIR}/init-bin" "${STAGE}/init"
chmod +x "${STAGE}/init"

(cd "${STAGE}" &&
    find . -print0 |
    cpio --null -oH newc --quiet |
        xz --check=crc32 -9 -e --threads=1) \
    > "${WORKDIR}/initramfs.img"
