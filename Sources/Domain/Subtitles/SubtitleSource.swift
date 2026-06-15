import Foundation

enum SubtitleSource: String, Codable, Hashable {
  case autoDetected
  case manual

  init(from decoder: Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    self = SubtitleSource(rawValue: rawValue) ?? .manual
  }

  var displayName: String {
    switch self {
    case .autoDetected:
      return "Auto"
    case .manual:
      return "Imported"
    }
  }
}
