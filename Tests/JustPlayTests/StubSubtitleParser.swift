import Foundation
@testable import JustPlay

struct StubSubtitleParser: SubtitleParser {
  var result: Result<[SubtitleCue], Error> = .success([])

  func parse(url: URL) throws -> [SubtitleCue] {
    try result.get()
  }
}
