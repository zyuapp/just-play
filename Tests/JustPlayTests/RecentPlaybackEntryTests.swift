import XCTest
@testable import JustPlay

final class RecentPlaybackEntryTests: XCTestCase {
  func testProgressIsZeroWhenDurationIsZero() {
    let entry = makeEntry(position: 30, duration: 0)
    XCTAssertEqual(entry.progress, 0, accuracy: 0.0001)
  }

  func testProgressIsRatioOfPositionToDuration() {
    let entry = makeEntry(position: 25, duration: 100)
    XCTAssertEqual(entry.progress, 0.25, accuracy: 0.0001)
  }

  func testProgressClampsAbovePositionToOne() {
    let entry = makeEntry(position: 150, duration: 100)
    XCTAssertEqual(entry.progress, 1.0, accuracy: 0.0001)
  }

  func testProgressClampsNegativePositionToZero() {
    let entry = makeEntry(position: -10, duration: 100)
    XCTAssertEqual(entry.progress, 0, accuracy: 0.0001)
  }

  func testIdEqualsFilePath() {
    let entry = makeEntry(filePath: "/movies/clip.mp4", position: 0, duration: 0)
    XCTAssertEqual(entry.id, "/movies/clip.mp4")
  }

  func testDisplayNameIsLastPathComponent() {
    let entry = makeEntry(filePath: "/movies/My Clip.mp4", position: 0, duration: 0)
    XCTAssertEqual(entry.displayName, "My Clip.mp4")
  }

  func testResolvedURLFallsBackToFilePathWithoutBookmark() {
    let entry = makeEntry(filePath: "/movies/clip.mp4", position: 0, duration: 0)
    XCTAssertEqual(entry.resolvedURL, URL(fileURLWithPath: "/movies/clip.mp4"))
  }

  func testResolvedURLResolvesValidBookmark() throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("RecentPlaybackEntryTests-\(UUID().uuidString).mp4")
    try Data().write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let bookmarkData = try fileURL.bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    var entry = makeEntry(filePath: "/stale/path.mp4", position: 0, duration: 0)
    entry.bookmarkData = bookmarkData

    XCTAssertEqual(entry.resolvedURL.standardizedFileURL, fileURL.standardizedFileURL)
  }

  func testNormalizedPathStandardizesURL() {
    let url = URL(fileURLWithPath: "/movies/../movies/clip.mp4")
    XCTAssertEqual(RecentPlaybackEntry.normalizedPath(for: url), "/movies/clip.mp4")
  }

  private func makeEntry(
    filePath: String = "/movies/clip.mp4",
    position: TimeInterval,
    duration: TimeInterval
  ) -> RecentPlaybackEntry {
    RecentPlaybackEntry(
      filePath: filePath,
      bookmarkData: nil,
      lastPlaybackPosition: position,
      duration: duration,
      lastOpenedAt: Date(),
      fileSize: nil,
      contentModificationDate: nil,
      selectedSubtitle: nil
    )
  }
}
