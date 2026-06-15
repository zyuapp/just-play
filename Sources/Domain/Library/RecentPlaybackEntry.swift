import Foundation

struct RecentPlaybackEntry: Codable, Identifiable {
  struct SubtitleSelection: Codable, Hashable {
    let filePath: String
    var bookmarkData: Data?
    let displayName: String
    let source: SubtitleSource

    var resolvedURL: URL {
      BookmarkResolver.resolveURL(bookmarkData: bookmarkData, fallbackPath: filePath)
    }
  }

  let filePath: String
  var bookmarkData: Data?
  var lastPlaybackPosition: TimeInterval
  var duration: TimeInterval
  var lastOpenedAt: Date
  var fileSize: Int64?
  var contentModificationDate: Date?
  var selectedSubtitle: SubtitleSelection?

  var id: String {
    filePath
  }

  var displayName: String {
    URL(fileURLWithPath: filePath).lastPathComponent
  }

  var resolvedURL: URL {
    BookmarkResolver.resolveURL(bookmarkData: bookmarkData, fallbackPath: filePath)
  }

  var progress: Double {
    guard duration > 0 else { return 0 }
    return min(max(lastPlaybackPosition / duration, 0), 1)
  }

  static func normalizedPath(for url: URL) -> String {
    url.standardizedFileURL.path
  }
}
