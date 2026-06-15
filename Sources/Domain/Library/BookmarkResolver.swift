import Foundation

enum BookmarkResolver {
  static func resolveURL(bookmarkData: Data?, fallbackPath: String) -> URL {
    guard let bookmarkData else {
      return URL(fileURLWithPath: fallbackPath)
    }

    var isStale = false
    if let url = try? URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withoutUI],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) {
      return url
    }

    return URL(fileURLWithPath: fallbackPath)
  }
}
