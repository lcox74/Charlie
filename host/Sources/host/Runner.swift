import Foundation
import Virtualization

// Headless runner that boots the guest and streams the console to stdout.
@MainActor
final class Runner: NSObject, VZVirtualMachineDelegate {
  private var vm: VZVirtualMachine?
  private var reader: ConsoleReader?
  private var guestIP: String?
  private var stopping = false
  private static let ipPattern = try! Regex(#"ip=(\d{1,3}(?:\.\d{1,3}){3})"#)

  func start() throws {
    guard let imageURL = GuestImage.url else { throw VMConfigurationError.missingGuestImage }

    let variableStoreURL = try Self.supportDirectory().appendingPathComponent("efi-vars.fd")

    let reader = ConsoleReader()
    reader.start()
    self.reader = reader

    Task { @MainActor in
      for await line in reader.lines { self.onConsoleLine(line) }
    }

    let config = try VMConfiguration.build(
      diskImageURL: imageURL,
      variableStoreURL: variableStoreURL,
      consoleWriteHandle: reader.writeHandle
    )

    let machine = VZVirtualMachine(configuration: config)
    machine.delegate = self
    vm = machine

    let memMiB = config.memorySize / (1024 * 1024)
    note(
      "starting VM (cpu=\(config.cpuCount), mem=\(memMiB)MiB, image=\(imageURL.lastPathComponent))"
    )

    Task { @MainActor in
      do {
        try await machine.start()
        note("VM running. Press Ctrl-C to shut down.")
      } catch {
        fail("vm.start failed: \(error.localizedDescription)")
      }
    }

    installSignalHandlers()
  }
  private func onConsoleLine(_ line: String) {
    print(line)

    if guestIP == nil,
      let match = line.firstMatch(of: Self.ipPattern),
      let captured = match[1].substring
    {

      guestIP = String(captured)

      note("guest IP \(guestIP!)")
    }
  }

  // Request a graceful ACPI shutdown; guestDidStop drives the actual exit. If
  // the guest doesn't comply within 6 seconds it will be terminated.
  private func requestStop() {
    guard !stopping, let vm else { return }

    stopping = true
    note("requesting graceful shutdown (ACPI power button)...")

    try? vm.requestStop()

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(6))

      note("guest did not stop in time; exiting")
      exit(1)
    }
  }

  // SIGINT/SIGTERM hop back onto the main actor and trigger a graceful stop.
  private func installSignalHandlers() {
    for sig in [SIGINT, SIGTERM] {
      signal(sig, SIG_IGN)

      let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      source.setEventHandler { [weak self] in
        Task { @MainActor in self?.requestStop() }
      }
      source.resume()

      Self.signalSources.append(source)
    }
  }

  private static var signalSources: [DispatchSourceSignal] = []

  private func note(_ message: String) {
    print(ANSI.blue(ANSI.bold("[host]")) + " \(message)")
  }

  private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(
      Data(
        (ANSI.blue(ANSI.bold("[host]"))
          + " FAIL: \(message)\n").utf8
      )
    )
    exit(1)
  }

  private static func supportDirectory() throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("castle", isDirectory: true)

    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    return dir
  }

  nonisolated func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    Task { @MainActor in
      self.note("guest stopped")
      exit(0)
    }
  }

  nonisolated func virtualMachine(
    _ virtualMachine: VZVirtualMachine,
    didStopWithError error: Error
  ) {
    Task { @MainActor in self.fail("guest stopped with error: \(error.localizedDescription)") }
  }
}
