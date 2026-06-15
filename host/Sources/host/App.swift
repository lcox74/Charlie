import Foundation

@main
enum HostMain {
  static func main() {
    MainActor.assumeIsolated {
      do {
        try Runner().start()
      } catch {
        FileHandle.standardError.write(Data("[charlie] setup failed: \(error)\n".utf8))
        exit(2)
      }
    }
    dispatchMain()
  }
}
