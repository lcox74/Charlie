import Foundation

enum ANSI {
  static let enabled: Bool = {
    if ProcessInfo.processInfo.environment["NO_COLOR"] != nil {
      return false
    }

    return isatty(fileno(stdout)) != 0
  }()

  private static func wrap(_ s: String, _ code: String) -> String {
    enabled
      ? "\u{1B}[\(code)m\(s)\u{1B}[0m"
      : s
  }

  static func bold(_ s: String) -> String { wrap(s, "1") }
  static func dim(_ s: String) -> String { wrap(s, "2") }

  static func yellow(_ s: String) -> String { wrap(s, "33") }
  static func blue(_ s: String) -> String { wrap(s, "34") }
  static func cyan(_ s: String) -> String { wrap(s, "36") }
}
