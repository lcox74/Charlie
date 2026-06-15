#!/bin/bash
#
# build-kernel.sh: compiles the custom bingo kernel.
# Runs inside the kbuilder Docker stage.
#
# Inputs (env vars, set by Dockerfile ARGs):
#   KERNEL_VERSION     e.g. 6.12.81
#   KERNEL_SHA256      tarball sha256 from kernel.org
#
# Mounts (provided by the Dockerfile RUN):
#   /kbuild            BuildKit cache; tarball + extracted source live here
#   /root/.ccache      ccache cache
#   /configs           bind mount of repo's kernel/ directory
#
# Output:
#   /out/boot/vmlinuz  arch-appropriate kernel image (bzImage on amd64,
#                      vmlinuz.efi on arm64)
#
set -euo pipefail

# Validate required environment variables
: "${KERNEL_VERSION:?ERROR: KERNEL_VERSION is not set}"
: "${KERNEL_SHA256:?ERROR: KERNEL_SHA256 is not set}"

# Validate config files exist
for cfg in /configs/config.common /configs/config.amd64 /configs/config.arm64; do
    [[ -f "${cfg}" ]] || { echo "ERROR: missing ${cfg}" >&2; exit 1; }
done

cd /kbuild

if [ ! -f "linux-${KERNEL_VERSION}.tar.xz" ]; then
    curl -fsSLo "linux-${KERNEL_VERSION}.tar.xz" \
        "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"
fi
echo "${KERNEL_SHA256}  linux-${KERNEL_VERSION}.tar.xz" | sha256sum -c -

if [ ! -d "linux-${KERNEL_VERSION}" ]; then
    tar -xf "linux-${KERNEL_VERSION}.tar.xz"
fi

cd "linux-${KERNEL_VERSION}"

export KBUILD_BUILD_USER=bingo KBUILD_BUILD_HOST=docker

ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)
        ARCH_FRAG=/configs/config.amd64
        MAKE_TARGET=bzImage
        KERNEL_OUT=arch/x86/boot/bzImage
        make CC="ccache gcc" HOSTCC="ccache gcc" defconfig
        ;;
    aarch64)
        ARCH_FRAG=/configs/config.arm64
        MAKE_TARGET=vmlinuz.efi
        KERNEL_OUT=arch/arm64/boot/vmlinuz.efi
        cp /configs/config.arm64.seed .config
        ;;
    *)
        echo "ERROR: unsupported arch ${ARCH}" >&2
        exit 1
        ;;
esac

scripts/kconfig/merge_config.sh -m .config /configs/config.common "${ARCH_FRAG}"
make CC="ccache gcc" HOSTCC="ccache gcc" olddefconfig
make -j"$(nproc)" CC="ccache gcc" HOSTCC="ccache gcc" "${MAKE_TARGET}"

mkdir -p /out/boot
cp "${KERNEL_OUT}" /out/boot/vmlinuz

ls -la /out/boot/vmlinuz
ccache -s || true
