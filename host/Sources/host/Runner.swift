import Foundation
import Virtualization

// A single line of output surfaced to the UI (and, in headless mode, stdout).
struct LogLine: Identifiable {
  enum Kind { case guest, host, error }

  let id: Int
  let kind: Kind
  let text: String
}

// Lifecycle of the guest, used to drive the toolbar buttons.
enum RunState: Equatable {
  case stopped, starting, running, stopping
}

// Boots the guest and streams the console. In headless mode it mirrors output
// to stdout and exits with the process; in GUI mode it publishes observable
// state (logs + run state) that SwiftUI renders.
@MainActor
final class Runner: NSObject, ObservableObject, VZVirtualMachineDelegate {
  @Published private(set) var logs: [LogLine] = []
  @Published private(set) var guestIP: String?
  @Published private(set) var state: RunState = .stopped

  let headless: Bool
  private var vm: VZVirtualMachine?
  private var reader: ConsoleReader?
  private var readerTask: Task<Void, Never>?
  private var forceStopTask: Task<Void, Never>?
  private var restartRequested = false
  private var logCounter = 0

  private static let ipPattern = try! Regex(#"ip=(\d{1,3}(?:\.\d{1,3}){3})"#)
  private static let maxLogLines = 5000
  private static var signalSources: [DispatchSourceSignal] = []

  init(headless: Bool) {
    self.headless = headless
    super.init()
  }

  func start() {
    guard state == .stopped else { return }
    state = .starting
    guestIP = nil

    guard let imageURL = GuestImage.url else {
      abortStart(
        "guest image missing: \(VMConfigurationError.missingGuestImage.localizedDescription)",
        code: 2)
      return
    }

    let config: VZVirtualMachineConfiguration
    do {
      let variableStoreURL = try Self.supportDirectory().appendingPathComponent("efi-vars.fd")

      let reader = ConsoleReader()
      reader.start()
      self.reader = reader

      readerTask = Task { @MainActor in
        for await line in reader.lines {
          self.onConsoleLine(line)
        }
      }

      config = try VMConfiguration.build(
        diskImageURL: imageURL,
        variableStoreURL: variableStoreURL,
        consoleWriteHandle: reader.writeHandle
      )
    } catch {
      abortStart("setup failed: \(error.localizedDescription)", code: 2)
      return
    }

    let machine = VZVirtualMachine(configuration: config)
    machine.delegate = self
    vm = machine

    let memMiB = config.memorySize / (1024 * 1024)
    log(
      "starting VM (cpu=\(config.cpuCount), mem=\(memMiB)MiB, image=\(imageURL.lastPathComponent))",
      .host)

    Task { @MainActor in
      do {
        try await machine.start()
        state = .running
        log("VM running." + (headless ? " Press Ctrl-C to shut down." : ""), .host)
      } catch {
        abortStart("vm.start failed: \(error.localizedDescription)", code: 1)
      }
    }

    installSignalHandlers()
  }

  // Logs a startup failure, releases anything partially set up, and returns to
  // the stopped state (exiting in headless mode).
  private func abortStart(_ message: String, code: Int32) {
    log(message, .error)
    teardown()
    state = .stopped
    if headless { exit(code) }
  }

  // Graceful ACPI shutdown. The guestDidStop/didStopWithError delegate drives
  // the actual transition to .stopped; if the guest ignores the request we
  // force it after 6 seconds.
  func stop() {
    guard state == .running, let vm else { return }

    state = .stopping
    log("requesting graceful shutdown (ACPI power button)...", .host)

    try? vm.requestStop()

    forceStopTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled, self.state == .stopping else { return }

      if self.headless {
        self.log("guest did not stop in time; exiting", .error)
        exit(1)
      }

      self.log("guest did not stop in time; forcing stop", .error)
      if let vm = self.vm { try? await vm.stop() }
      self.handleStopped(error: nil)
    }
  }

  func restart() {
    switch state {
    case .running:
      restartRequested = true
      stop()
    case .stopped:
      start()
    case .starting, .stopping:
      break
    }
  }

  // Hits the guest's HTTP server (listens on :8080) and logs the response.
  func sendRequest() {
    guard let ip = guestIP else {
      log("no guest IP yet", .error)
      return
    }

    let urlString = "http://\(ip):8080/"
    guard let url = URL(string: urlString) else { return }

    log("GET \(urlString)", .host)

    Task { @MainActor in
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(decoding: data, as: UTF8.self)
          .trimmingCharacters(in: .whitespacesAndNewlines)

        log("HTTP \(status): \(body)", .host)
      } catch {
        log("request failed: \(error.localizedDescription)", .error)
      }
    }
  }

  private func onConsoleLine(_ line: String) {
    log(line, .guest)

    if guestIP == nil,
      let match = line.firstMatch(of: Self.ipPattern),
      let captured = match[1].substring
    {
      guestIP = String(captured)
      log("guest IP \(guestIP!)", .host)
    }
  }

  // Tears down VM-owned resources without changing run state.
  private func teardown() {
    forceStopTask?.cancel()
    forceStopTask = nil
    readerTask?.cancel()
    readerTask = nil
    reader?.stop()
    reader = nil
    vm = nil
  }

  private func handleStopped(error: Error?) {
    guard state != .stopped else { return }

    teardown()
    state = .stopped

    if let error {
      log("guest stopped with error: \(error.localizedDescription)", .error)
    } else {
      log("guest stopped", .host)
    }

    if headless { exit(error == nil ? 0 : 1) }

    if restartRequested {
      restartRequested = false
      log("restarting...", .host)
      start()
    }
  }

  private func installSignalHandlers() {
    guard Self.signalSources.isEmpty else { return }

    for sig in [SIGINT, SIGTERM] {
      signal(sig, SIG_IGN)

      let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      source.setEventHandler { [weak self] in
        Task { @MainActor in self?.stop() }
      }
      source.resume()

      Self.signalSources.append(source)
    }
  }

  // Appends to the observable buffer; in headless mode also writes to the
  // terminal so the CLI behaves as before.
  private func log(_ text: String, _ kind: LogLine.Kind) {
    logCounter += 1
    logs.append(LogLine(id: logCounter, kind: kind, text: text))
    if logs.count > Self.maxLogLines {
      logs.removeFirst(logs.count - Self.maxLogLines)
    }

    guard headless else { return }

    let prefix = ANSI.blue(ANSI.bold("[host]"))
    switch kind {
    case .guest:
      print(text)
    case .host:
      print(prefix + " " + text)
    case .error:
      FileHandle.standardError.write(Data((prefix + " FAIL: \(text)\n").utf8))
    }
  }

  private static func supportDirectory() throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("charlie", isDirectory: true)

    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    return dir
  }

  nonisolated func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    Task { @MainActor in self.handleStopped(error: nil) }
  }

  nonisolated func virtualMachine(
    _ virtualMachine: VZVirtualMachine,
    didStopWithError error: Error
  ) {
    Task { @MainActor in self.handleStopped(error: error) }
  }
}
