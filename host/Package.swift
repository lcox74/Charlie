// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "host",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "host", targets: ["host"])
  ],
  targets: [
    .executableTarget(
      name: "host",
      resources: [.copy("bingo.arm64.img")]
    )
  ],
  swiftLanguageModes: [.v6]
)
