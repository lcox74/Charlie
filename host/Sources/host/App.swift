import AppKit
import Foundation
import SwiftUI

// Branch before any UI starts: `--headless` keeps the original CLI behaviour
// (boot the VM, stream the console to stdout, exit with the guest); otherwise
// hand off to the SwiftUI app.
@main
enum HostMain {
  static func main() {
    if CommandLine.arguments.contains("--headless") {
      MainActor.assumeIsolated { Runner(headless: true).start() }
      dispatchMain()
    } else {
      CharlieApp.main()
    }
  }
}

struct CharlieApp: App {
  @StateObject private var runner = Runner(headless: false)

  init() {
    NSApplication.shared.setActivationPolicy(.regular)
  }

  var body: some Scene {
    Window("charlie", id: "main") {
      ContentView(runner: runner)
        .frame(minWidth: 720, minHeight: 440)
        .onAppear {
          NSApplication.shared.activate(ignoringOtherApps: true)
          runner.start()
        }
    }
  }
}
