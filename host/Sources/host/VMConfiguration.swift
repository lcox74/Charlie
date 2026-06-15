import Foundation
import Virtualization

// Locate Bingo Image from bundled package resources
enum GuestImage {
  static let resourceName = "bingo.arm64"
  static let resourceExtension = "img"

  static var url: URL? {
    Bundle.module.url(forResource: resourceName, withExtension: resourceExtension)
  }
}

enum VMConfigurationError: LocalizedError {
  case missingGuestImage

  var errorDescription: String? {
    switch self {
    case .missingGuestImage:
      return "Guest image \(GuestImage.resourceName).\(GuestImage.resourceExtension) is not bundled"
    }
  }
}

enum VMConfiguration {
  // Pinned a local unicast MAC so the host can find the Guest's DHCP lease
  // after boot.
  static var macAddress: VZMACAddress { VZMACAddress(string: "ce:a5:71:e0:00:01")! }

  static let requestedMemorySize: UInt64 = 256 * 1024 * 1024  // 256 MB
  static let requestedCPUCount = 1  // 1 vCPU

  static func build(
    diskImageURL: URL,
    variableStoreURL: URL,
    consoleWriteHandle: FileHandle
  ) throws -> VZVirtualMachineConfiguration {
    let config = VZVirtualMachineConfiguration()

    config.cpuCount = min(
      max(
        requestedCPUCount,
        VZVirtualMachineConfiguration.minimumAllowedCPUCount
      ),
      VZVirtualMachineConfiguration.maximumAllowedCPUCount
    )
    config.memorySize = min(
      max(
        requestedMemorySize,
        VZVirtualMachineConfiguration.minimumAllowedMemorySize
      ),
      VZVirtualMachineConfiguration.maximumAllowedMemorySize
    )

    // Setup EFI bootloader
    let bootLoader = VZEFIBootLoader()
    bootLoader.variableStore = try efiVariableStore(at: variableStoreURL)
    config.bootLoader = bootLoader

    // Attach rootfs disk as read-only
    let attachment = try VZDiskImageStorageDeviceAttachment(url: diskImageURL, readOnly: true)
    config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: attachment)]

    // Setup Network as a vmnet shared NAT device.
    let network = VZVirtioNetworkDeviceConfiguration()
    network.attachment = VZNATNetworkDeviceAttachment()
    network.macAddress = macAddress
    config.networkDevices = [network]

    // Set entropy so DHCP has enough randomness at boot
    config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

    // Wire virtio-console (hvc0)
    let console = VZVirtioConsoleDeviceSerialPortConfiguration()
    console.attachment = VZFileHandleSerialPortAttachment(
      fileHandleForReading: nil,
      fileHandleForWriting: consoleWriteHandle
    )
    config.serialPorts = [console]

    // Setup a vsock for later direct host <-> guest IPC. Will play with this
    // once I have something working.
    config.socketDevices = [VZVirtioSocketDeviceConfiguration()]

    try config.validate()
    return config
  }

  private static func efiVariableStore(at url: URL) throws -> VZEFIVariableStore {
    if FileManager.default.fileExists(atPath: url.path) {
      return VZEFIVariableStore(url: url)
    }
    return try VZEFIVariableStore(creatingVariableStoreAt: url)
  }
}
