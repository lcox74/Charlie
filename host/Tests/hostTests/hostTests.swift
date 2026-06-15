import Foundation
import Testing

@testable import host

// Drains a reader's line stream into an array. The stream finishes when the
// write handle is closed (EOF), so callers must close before awaiting.
private func collectLines(from reader: ConsoleReader) async -> [String] {
  var lines: [String] = []
  for await line in reader.lines {
    lines.append(line)
  }
  return lines
}

@Suite("ConsoleReader")
struct ConsoleReaderTests {
  @Test("splits on newline and trims trailing carriage returns")
  func splitsAndTrimsCRLF() async throws {
    let reader = ConsoleReader()
    reader.start()

    let write = reader.writeHandle
    write.write(Data("hello\r\nworld\r\n".utf8))
    try write.close()

    let lines = await collectLines(from: reader)
    #expect(lines == ["hello", "world"])
  }

  @Test("emits each line of a multi-line chunk")
  func multipleLinesInOneChunk() async throws {
    let reader = ConsoleReader()
    reader.start()

    let write = reader.writeHandle
    write.write(Data("one\ntwo\nthree\n".utf8))
    try write.close()

    let lines = await collectLines(from: reader)
    #expect(lines == ["one", "two", "three"])
  }

  @Test("preserves empty lines between content")
  func preservesEmptyLines() async throws {
    let reader = ConsoleReader()
    reader.start()

    let write = reader.writeHandle
    write.write(Data("a\n\nb\n".utf8))
    try write.close()

    let lines = await collectLines(from: reader)
    #expect(lines == ["a", "", "b"])
  }

  @Test("buffers a partial line until a newline arrives")
  func buffersPartialLineAcrossWrites() async throws {
    let reader = ConsoleReader()
    reader.start()

    let write = reader.writeHandle
    write.write(Data("par".utf8))
    write.write(Data("tial\nrest\n".utf8))
    try write.close()

    let lines = await collectLines(from: reader)
    #expect(lines == ["partial", "rest"])
  }

  @Test("drops a trailing line that has no terminating newline at EOF")
  func dropsUnterminatedTrailingLine() async throws {
    let reader = ConsoleReader()
    reader.start()

    let write = reader.writeHandle
    write.write(Data("complete\nincomplete".utf8))
    try write.close()

    let lines = await collectLines(from: reader)
    #expect(lines == ["complete"])
  }

  @Test("yields nothing for an immediately closed stream")
  func emptyStreamYieldsNothing() async throws {
    let reader = ConsoleReader()
    reader.start()

    try reader.writeHandle.close()

    let lines = await collectLines(from: reader)
    #expect(lines.isEmpty)
  }
}

@Suite("Runner.parseGuestIP")
struct ParseGuestIPTests {
  @Test("extracts a dotted-quad from an ip= token")
  func extractsIP() {
    #expect(
      Runner.parseGuestIP(from: "configured ip=192.168.64.7 gw=192.168.64.1") == "192.168.64.7")
  }

  @Test("matches an ip= token anywhere in the line")
  func matchesAnywhere() {
    #expect(Runner.parseGuestIP(from: "ip=10.0.0.1") == "10.0.0.1")
    #expect(Runner.parseGuestIP(from: "[net] lease acquired, ip=172.16.5.42") == "172.16.5.42")
  }

  @Test("returns nil when no ip= token is present")
  func returnsNilWithoutToken() {
    #expect(Runner.parseGuestIP(from: "booting kernel") == nil)
    #expect(Runner.parseGuestIP(from: "address 192.168.0.1 assigned") == nil)
  }

  @Test("ignores an ip= token with no value")
  func returnsNilForEmptyValue() {
    #expect(Runner.parseGuestIP(from: "ip=") == nil)
    #expect(Runner.parseGuestIP(from: "ip=not-an-address") == nil)
  }

  @Test("returns the first ip when several appear")
  func returnsFirstMatch() {
    #expect(Runner.parseGuestIP(from: "ip=10.0.0.1 alt ip=10.0.0.2") == "10.0.0.1")
  }
}

@Suite("ANSI")
struct ANSITests {
  // `enabled` is decided once from the environment (NO_COLOR / tty), so assert
  // the wrap behaviour against whatever it resolved to in this process.
  @Test("wraps text only when colour is enabled")
  func wrapMatchesEnabledState() {
    let result = ANSI.bold("charlie")
    if ANSI.enabled {
      #expect(result == "\u{1B}[1mcharlie\u{1B}[0m")
    } else {
      #expect(result == "charlie")
    }
  }
}
