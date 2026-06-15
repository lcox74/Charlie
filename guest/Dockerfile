# Stage 1: Build the Golang Binary
# Use BUILDPLATFORM to run Go natively and cross-compile via GOARCH
FROM --platform=$BUILDPLATFORM golang:1.26-alpine3.23 AS gobuilder

ARG TARGETARCH

WORKDIR /src

COPY src/go.mod src/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY src/ ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} \
    go build -ldflags="-s -w" -o /bingo-init ./cmd/init

# Stage 2: Build the Kernel
FROM alpine:3.23 AS kbuilder

ARG KERNEL_VERSION
ARG KERNEL_SHA256
ARG TARGETARCH

RUN apk add --no-cache \
    bash build-base bc bison flex \
    elfutils-dev openssl-dev perl \
    linux-headers xz gzip tar curl \
    findutils coreutils ccache

COPY kernel /configs
COPY scripts /scripts

RUN mkdir -p /kbuild
RUN --mount=type=cache,target=/kbuild,sharing=locked,id=bingo-kbuild-${TARGETARCH} \
    --mount=type=cache,target=/root/.ccache,sharing=locked,id=bingo-ccache-${TARGETARCH} \
    --mount=type=bind,source=kernel,target=/configs \
    --mount=type=bind,source=scripts,target=/scripts \
    /scripts/build-kernel.sh

# Stage 3: Build the Unified Kernel Image.
FROM debian:trixie-slim AS ukibuilder

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        systemd-boot-efi systemd-ukify binutils xz-utils cpio && \
    rm -rf /var/lib/apt/lists/*

COPY --from=kbuilder  /out/boot/vmlinuz /uki/vmlinuz
COPY --from=gobuilder /bingo-init   /uki/init-bin
COPY kernel/cmdline                     /uki/cmdline
COPY scripts/init-mkinitramfs.sh        /uki/mk.sh
COPY scripts/build-uki.sh               /uki/build-uki.sh

RUN /uki/mk.sh /uki
RUN /uki/build-uki.sh

# Stage 4a: Assemble GPT+FAT disk image
FROM alpine:3.23 AS imgbuilder

ARG TARGETARCH

RUN apk add --no-cache bash parted dosfstools mtools coreutils

COPY --from=ukibuilder /uki/BOOT.EFI /stage/BOOT.EFI
COPY scripts/assemble-img.sh         /stage/assemble-img.sh

RUN /stage/assemble-img.sh /stage/BOOT.EFI /out/bingo.${TARGETARCH}.img

# Stage 4b: Export UEFI Image
FROM scratch AS export-img

ARG TARGETARCH

COPY --from=imgbuilder /out/bingo.${TARGETARCH}.img /
ENTRYPOINT ["/bingo.${TARGETARCH}.img"]

