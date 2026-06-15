import Foundation

protocol SubtitleParser {
  func parse(url: URL) throws -> [SubtitleCue]
}
