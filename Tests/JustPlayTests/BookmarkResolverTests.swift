import XCTest
@testable import JustPlay

final class BookmarkResolverTests: XCTestCase {
  func testResolvesFallbackWhenBookmarkIsNil() {
    let url = BookmarkResolver.resolveURL(bookmarkData: nil, fallbackPath: "/movies/clip.mp4")
    XCTAssertEqual(url, URL(fileURLWithPath: "/movies/clip.mp4"))
  }

  func testResolvesFallbackWhenBookmarkIsInvalid() {
    let url = BookmarkResolver.resolveURL(bookmarkData: Data([0x00, 0x01, 0x02]), fallbackPath: "/movies/clip.mp4")
    XCTAssertEqual(url, URL(fileURLWithPath: "/movies/clip.mp4"))
  }

  func testResolvesValidBookmark() throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("BookmarkResolverTests-\(UUID().uuidString).mp4")
    try Data().write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let bookmarkData = try fileURL.bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    let resolved = BookmarkResolver.resolveURL(bookmarkData: bookmarkData, fallbackPath: "/stale/path.mp4")
    XCTAssertEqual(resolved.standardizedFileURL, fileURL.standardizedFileURL)
  }
}
