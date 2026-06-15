# Bingo

**B**ootable **I**mage i**n** **Go**.

A minimal bootable Linux image (~8 MiB) that runs a statically compiled Go
HTTP server as the only userspace binary. It boots directly from UEFI firmware
without a traditional init system, shell, or container runtime.

## How It Works

The Go binary runs as PID 1 and handles all system initialisation:

1. Mounts virtual filesystems (`/proc`, `/sys`, `/dev`, `/tmp`, `/run`)
2. Brings up network interfaces using netlink sockets
3. Runs a pure Go DHCP client to obtain IP configuration
4. Listens for ACPI power button events for graceful shutdown
5. Starts an HTTP server on port `:8080`

## Building

Requires Docker for the build process.

```bash
# Build UEFI disk image for arm64
just build arm64 uefi

# Build UEFI disk image for amd64
just build amd64 uefi

# Build legacy (SeaBIOS) bootable ISO for amd64
just build amd64 legacy
```

Output files are placed in the `out/` directory:

- `bingo.amd64.img` / `bingo.arm64.img` (UEFI disk images)
- `bingo.amd64.iso` (Bootable ISOs)

## Running

Requires QEMU.

```bash
# Build and run in QEMU
just run amd64 uefi
just run arm64 uefi
```

Once booted, the HTTP server responds on port `:8080` with "Hello, World!".

## Project Structure

```
bingo/
├── Dockerfile          # Multi stage Docker build
├── justfile            # Build automation
├── src/                # Go source code
│   ├── cmd/init        # Entrypoint
│   └── internal/
│       ├── acpi/       # Power button handling
│       ├── app/        # HTTP server
│       ├── boot/       # Filesystem mounting
│       └── network/    # Interface and DHCP management
├── kernel/             # Kernel configuration files
└── scripts/            # Build and assembly scripts
```

## Technical Details

**Kernel**: Custom Linux 6.12 LTS kernel (~3.7 MiB) with only essential
features enabled, including VirtIO drivers, EFI stub, initramfs support, and
networking. Modules, unnecessary filesystems, USB, graphics, and debugging are
disabled.

**Unified Kernel Image**: The final image packages the kernel, initramfs, and
boot parameters into a single UEFI executable (`EFI/BOOT/BOOTX64.EFI`).

## Architecture Support

- **amd64**: UEFI and legacy (SeaBIOS) boot
- **arm64**: UEFI boot only

