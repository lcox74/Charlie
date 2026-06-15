
home := env_var('HOME')
swift := if path_exists(home / ".swiftly/bin/swift") == "true" { home / ".swiftly/bin/swift" } else { "swift" }

# Show available recipes.
[default]
default:
    @just --list


# Build the guest disk image using Docker
[doc('Build the bingo guest image (arm64 uefi)')]
guest-build:
    cd guest && just build
    cp out/bingo.arm64.img ../host/Sources/host/bingo.arm64.img

# Build the host app (debug or release).
[doc('Build the host app (debug or release)')]
build target="debug":
    #!/usr/bin/env bash
    set -eo pipefail

    cd guest && just build
    cp out/bingo.arm64.img ../host/Sources/host/bingo.arm64.img

    cd ..

    config=()
    if [ "{{target}}" = "release" ]; then config=(-c release); fi

    {{swift}} build "${config[@]}" --package-path host

    bin="$({{swift}} build "${config[@]}" --package-path host --show-bin-path)/host"
    codesign --force --sign - --entitlements host/host.entitlements "$bin"

# Run the host app (debug or release).
[doc('Build, codesign, and run the host app (debug or release)')]
run target="debug": build
    #!/usr/bin/env bash
    set -eo pipefail

    config=()
    if [ "{{target}}" = "release" ]; then config=(-c release); fi

    bin="$({{swift}} build "${config[@]}" --package-path host --show-bin-path)/host"

    exec "$bin"


# Run the host test suite.
[doc('Run the host test suite')]
test:
    {{swift}} test --package-path host

# Remove host build artifacts and the synced image resource.
[doc('Remove host build artifacts')]
clean:
    rm -rf host/.build host/Sources/host/bingo.arm64.img
