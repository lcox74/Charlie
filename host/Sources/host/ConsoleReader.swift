import Foundation

// Reads the guest's virtio-console output and exposes it as an ordered stream
// of lines.
final class ConsoleReader: @unchecked Sendable {
  let lines: AsyncStream<String>

  private let pipe = Pipe()
  private let continuation: AsyncStream<String>.Continuation
  private var buffer = Data()

  // The handle the VM should write guest console output into.
  var writeHandle: FileHandle { pipe.fileHandleForWriting }

  init() {
    var captured: AsyncStream<String>.Continuation!

    lines = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
    continuation = captured
  }

  func start() {
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      guard let self else { return }

      let data = handle.availableData
      if data.isEmpty {
        self.finish()
        return
      }

      self.ingest(data)
    }
  }

  func stop() {
    finish()
  }

  private func finish() {
    pipe.fileHandleForReading.readabilityHandler = nil
    continuation.finish()
  }

  // Accumulate bytes and emit complete newline-terminated lines. Carriage
  // returns are trimmed so kernel output (which uses CRLF) reads cleanly.
  private func ingest(_ data: Data) {
    buffer.append(data)

    while let newline = buffer.firstIndex(of: 0x0A) {
      let lineData = buffer[buffer.startIndex..<newline]

      buffer.removeSubrange(buffer.startIndex...newline)

      let line = String(decoding: lineData, as: UTF8.self)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))

      continuation.yield(line)
    }
  }
}
