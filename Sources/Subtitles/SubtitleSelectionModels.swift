import Foundation

struct SubtitleTrackOption: Identifiable, Hashable {
  let id: String
  let displayName: String
  let sourceLabel: String
}

struct SubtitleLanguageOption: Identifiable, Hashable {
  let code: String
  let title: String

  var id: String {
    code
  }

  static let anyCode = "any"

  static let all: [SubtitleLanguageOption] = [
    SubtitleLanguageOption(code: anyCode, title: "Any Language"),
    SubtitleLanguageOption(code: "en", title: "English"),
    SubtitleLanguageOption(code: "es", title: "Spanish"),
    SubtitleLanguageOption(code: "fr", title: "French"),
    SubtitleLanguageOption(code: "de", title: "German"),
    SubtitleLanguageOption(code: "it", title: "Italian"),
    SubtitleLanguageOption(code: "pt", title: "Portuguese"),
    SubtitleLanguageOption(code: "ja", title: "Japanese"),
    SubtitleLanguageOption(code: "ko", title: "Korean"),
    SubtitleLanguageOption(code: "zh", title: "Chinese")
  ]

  static let supportedCodes: Set<String> = Set(all.map(\.code))
}
