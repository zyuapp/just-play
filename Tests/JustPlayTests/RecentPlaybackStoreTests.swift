import XCTest
@testable import JustPlay

final class RecentPlaybackStoreTests: XCTestCase {
  private var cleanupDirectories: [URL] = []

  override func tearDown() {
    for url in cleanupDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    cleanupDirectories.removeAll()
    super.tearDown()
  }

  func testSaveThenLoadRoundTripsEntries() {
    let bundleID = makeBundleID()
    let recents = [
      makeEntry(filePath: "/movies/a.mp4", position: 10, duration: 100, openedAt: date(200)),
      makeEntry(filePath: "/movies/b.mp4", position: 20, duration: 200, openedAt: date(100))
    ]
    let archived = [makeEntry(filePath: "/movies/c.mp4", position: 0, duration: 50, openedAt: date(50))]

    makeStore(bundleID).saveState(.init(recentEntries: recents, archivedEntries: archived))

    let loaded = makeStore(bundleID).loadState()

    XCTAssertEqual(loaded.recentEntries.map(\.filePath), ["/movies/a.mp4", "/movies/b.mp4"])
    XCTAssertEqual(loaded.recentEntries[0].lastPlaybackPosition, 10, accuracy: 0.001)
    XCTAssertEqual(loaded.archivedEntries.map(\.filePath), ["/movies/c.mp4"])
  }

  func testLoadReturnsEmptyWhenNoFileExists() {
    let state = makeStore(makeBundleID()).loadState()
    XCTAssertTrue(state.recentEntries.isEmpty)
    XCTAssertTrue(state.archivedEntries.isEmpty)
  }

  func testEntriesAreSortedByLastOpenedDescending() {
    let bundleID = makeBundleID()
    let entries = [
      makeEntry(filePath: "/movies/old.mp4", position: 0, duration: 10, openedAt: date(100)),
      makeEntry(filePath: "/movies/new.mp4", position: 0, duration: 10, openedAt: date(300)),
      makeEntry(filePath: "/movies/mid.mp4", position: 0, duration: 10, openedAt: date(200))
    ]

    makeStore(bundleID).saveState(.init(recentEntries: entries, archivedEntries: []))

    let loaded = makeStore(bundleID).loadState()

    XCTAssertEqual(loaded.recentEntries.map(\.filePath), ["/movies/new.mp4", "/movies/mid.mp4", "/movies/old.mp4"])
  }

  func testLoadsLegacyPayloadWithoutArchivedEntries() throws {
    let bundleID = makeBundleID()
    let json = """
    {
      "schemaVersion": 1,
      "entries": [
        {
          "filePath": "/movies/legacy.mp4",
          "lastPlaybackPosition": 42,
          "duration": 120,
          "lastOpenedAt": "2026-01-01T00:00:00Z"
        }
      ]
    }
    """
    try writeStoreFile(bundleIdentifier: bundleID, contents: Data(json.utf8))

    let loaded = makeStore(bundleID).loadState()

    XCTAssertEqual(loaded.recentEntries.map(\.filePath), ["/movies/legacy.mp4"])
    XCTAssertEqual(loaded.recentEntries.first?.lastPlaybackPosition ?? -1, 42, accuracy: 0.001)
    XCTAssertTrue(loaded.archivedEntries.isEmpty)
  }

  func testLoadReturnsEmptyForCorruptData() throws {
    let bundleID = makeBundleID()
    try writeStoreFile(bundleIdentifier: bundleID, contents: Data("not json".utf8))

    let loaded = makeStore(bundleID).loadState()

    XCTAssertTrue(loaded.recentEntries.isEmpty)
    XCTAssertTrue(loaded.archivedEntries.isEmpty)
  }

  private func makeBundleID() -> String {
    let bundleID = "com.justplay.tests.\(UUID().uuidString)"
    cleanupDirectories.append(storeDirectoryURL(bundleIdentifier: bundleID))
    return bundleID
  }

  private func makeStore(_ bundleIdentifier: String) -> RecentPlaybackStore {
    RecentPlaybackStore(
      bundleIdentifier: bundleIdentifier,
      legacyBundleIdentifier: "com.justplay.tests.legacy.\(UUID().uuidString)"
    )
  }

  private func storeDirectoryURL(bundleIdentifier: String) -> URL {
    let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)

    return appSupportURL.appendingPathComponent(bundleIdentifier, isDirectory: true)
  }

  private func writeStoreFile(bundleIdentifier: String, contents: Data) throws {
    let directoryURL = storeDirectoryURL(bundleIdentifier: bundleIdentifier)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let fileURL = directoryURL.appendingPathComponent("recent-playback.v1.json")
    try contents.write(to: fileURL)
  }

  private func date(_ secondsSinceReference: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: secondsSinceReference)
  }

  private func makeEntry(
    filePath: String,
    position: TimeInterval,
    duration: TimeInterval,
    openedAt: Date
  ) -> RecentPlaybackEntry {
    RecentPlaybackEntry(
      filePath: filePath,
      bookmarkData: nil,
      lastPlaybackPosition: position,
      duration: duration,
      lastOpenedAt: openedAt,
      fileSize: nil,
      contentModificationDate: nil,
      selectedSubtitle: nil
    )
  }
}
