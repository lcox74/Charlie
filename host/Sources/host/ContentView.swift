import SwiftUI

struct ContentView: View {
  @ObservedObject var runner: Runner

  var body: some View {
    VStack(spacing: 0) {
      ControlBar(runner: runner)
      Divider()
      LogConsole(lines: runner.logs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct ControlBar: View {
  @ObservedObject var runner: Runner

  var body: some View {
    HStack(spacing: 12) {
      Button {
        runner.start()
      } label: {
        Label("Start", systemImage: "play.fill")
      }
      .disabled(runner.state != .stopped)

      Button {
        runner.stop()
      } label: {
        Label("Stop", systemImage: "stop.fill")
      }
      .disabled(runner.state != .running)

      Button {
        runner.restart()
      } label: {
        Label("Restart", systemImage: "arrow.clockwise")
      }
      .disabled(runner.state == .starting || runner.state == .stopping)

      Divider().frame(height: 20)

      StatusPill(state: runner.state)

      Spacer()

      if let ip = runner.guestIP {
        Text(ip)
          .font(.system(.callout, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      Button {
        runner.sendRequest()
      } label: {
        Label("API Request", systemImage: "network")
      }
      .disabled(runner.state != .running || runner.guestIP == nil)
    }
    .padding(10)
  }
}

private struct StatusPill: View {
  let state: RunState

  private var color: Color {
    switch state {
    case .stopped: return .secondary
    case .starting, .stopping: return .orange
    case .running: return .green
    }
  }

  private var label: String {
    switch state {
    case .stopped: return "Stopped"
    case .starting: return "Starting"
    case .running: return "Running"
    case .stopping: return "Stopping"
    }
  }

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(color)
        .frame(width: 9, height: 9)
      Text(label)
        .font(.callout.weight(.medium))
    }
  }
}

private struct LogConsole: View {
  let lines: [LogLine]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 1) {
        ForEach(lines) { line in
          Text(text(for: line))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color(for: line.kind))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(line.id)
        }
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .defaultScrollAnchor(.bottom)
    .background(Color(nsColor: .textBackgroundColor))
  }

  private func text(for line: LogLine) -> String {
    switch line.kind {
    case .host: return "[host] " + line.text
    case .error: return "[host] FAIL: " + line.text
    case .guest: return line.text.isEmpty ? " " : line.text
    }
  }

  private func color(for kind: LogLine.Kind) -> Color {
    switch kind {
    case .guest: return .primary
    case .host: return .accentColor
    case .error: return .red
    }
  }
}
