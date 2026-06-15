# Charlie

The [WWDC26: Expand the capabilities of your Virtualization app] session
reminded me that Apple's Virtualization Framework exists and is quite cool. I've
been wanting to play with it for a couple of work projects but never got around
to it, and I happen to have the perfect test image in [Bingo] to try it out on.

Introducing Charlie: a host application written in Swift that uses the macOS
Virtualization Framework to boot and run [Bingo] (a custom Linux guest). The
guest has no distro or shell, just a simple network API, so it's about as
minimal as it gets. Everything runs in Apple's built-in hypervisor with no other
applications or dependencies required.

This project wasn't built with Xcode, as I don't have enough storage on my Mac
Mini (I got the smallest storage size). So instead I use [Swiftly] to get the
Swift toolchain directly, and `codesign` to sign the binary so it's allowed to
run.

> **NOTE:** This project leans on Apple's `Virtualization.framework` for the
> host side, so it only runs on Apple Silicon macOS. The guest is built as an
> arm64 UEFI disk image, so everything here is arm64 end to end.

## Structure

The project is split into two halves:

- **host:** the macOS app (codename `charlie`) that configures and boots the VM
- **guest:** the Linux image (codename `bingo`) that runs inside it

The host is a small Swift executable that builds a
`VZVirtualMachineConfiguration`, attaches the guest image as a read-only disk,
wires up a NAT network device and a virtio console, and boots it headless while
streaming the guest's console to stdout. It also watches the console for the
guest's IP and handles `Ctrl-C` by asking for a graceful ACPI shutdown.

The guest is a Go program that runs as PID 1. It mounts the basics, brings up
the interfaces, acquires a DHCP lease, sets a hostname, and then starts an HTTP
server on port 8080. It listens for the ACPI power button so the host's graceful
shutdown request actually does something.

This will probably grow a vsock based host <-> guest IPC channel at some point.
The socket device is already wired up on the host side, I just haven't done
anything with it yet.

## Requirements

You'll want an Apple Silicon Mac and a couple of toolchains. The short list:

- macOS 26 (Tahoe) or newer
- Swift 6.3 toolchain
- Docker (the guest image is built inside a container)
- just

I don't have enough storage on my device for a full Xcode install, so I install
the Swift toolchain directly from the Swift site using [Swiftly]. The host
`justfile` reaches for the swiftly binaries first but falls back to the system
default.

The guest image is built entirely inside Docker (kernel, initramfs, UKI, and the
final GPT/FAT disk image), so you don't need a kernel build environment on the
host. You just need Docker able to build `linux/arm64`.

You also need the Xcode command line tools (`xcode-select --install`), which
provide `codesign` and are much smaller than the full Xcode suite.

## Building

Building the host also builds the guest image and copies it in as a bundled
resource, so a single command gets you the whole thing. Debug is the default.

```sh
just build            # debug build
just build release    # release build
```

The host binary has to be codesigned with the virtualization entitlement before
it can boot a VM. The `build` recipe does that for you automatically after the
Swift build finishes.

## Running

```sh
just run              # debug
just run release      # release
```

This boots the guest headless and streams its console to your terminal. Once the
guest has a lease the host prints the guest IP, at which point the HTTP server
is reachable on port 8080. Press `Ctrl-C` to request a graceful shutdown; the
host sends the ACPI power signal and gives the guest a few seconds to stop
cleanly before being terminated.

The guest's runtime state (its EFI variable store) lives under Application
Support in a `charlie` directory, so the EFI vars persist across runs.

## License

Released under the [MIT License](LICENSE).

[Swiftly]: https://www.swift.org/install/
[WWDC26: Expand the capabilities of your Virtualization app]: https://www.youtube.com/watch?v=Bz5YSYJ8pzo
[Bingo]: https://github.com/lcox74/Bingo
