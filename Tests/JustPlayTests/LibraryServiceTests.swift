import XCTest
@testable import JustPlay

@MainActor
final class LibraryServiceTests: XCTestCase {
  func testArchiveMovesEntryFromRecentsToArchived() {
    let entry = makeEntry(path: "/movies/a.mp4", openedAt: 100)
    let service = makeService(recentEntries: [entry])

    service.archive(entry)

    XCTAssertTrue(service.recentEntries.isEmpty)
    XCTAssertEqual(service.archivedEntries.map(\.filePath), ["/movies/a.mp4"])
  }

  func testArchiveKeepsArchivedSortedByMostRecentlyOpened() {
    let older = makeEntry(path: "/movies/old.mp4", openedAt: 100)
    let newer = makeEntry(path: "/movies/new.mp4", openedAt: 200)
    let service = makeService(recentEntries: [older, newer])

    service.archive(older)
    service.archive(newer)

    XCTAssertEqual(service.archivedEntries.map(\.filePath), ["/movies/new.mp4", "/movies/old.mp4"])
  }

  func testArchiveDeduplicatesEntryAlreadyPresentInArchive() {
    let entry = makeEntry(path: "/movies/a.mp4", openedAt: 100)
    let service = makeService(recentEntries: [entry], archivedEntries: [entry])

    service.archive(entry)

    XCTAssertEqual(service.archivedEntries.map(\.filePath), ["/movies/a.mp4"])
    XCTAssertTrue(service.recentEntries.isEmpty)
  }

  func testRestoreArchivedMovesEntryBackToRecents() {
    let entry = makeEntry(path: "/movies/a.mp4", openedAt: 100)
    let service = makeService(archivedEntries: [entry])

    service.restoreArchived(entry)

    XCTAssertTrue(service.archivedEntries.isEmpty)
    XCTAssertEqual(service.recentEntries.map(\.filePath), ["/movies/a.mp4"])
  }

  func testDeleteArchivedPermanentlyRemovesEntryEntirely() {
    let entry = makeEntry(path: "/movies/a.mp4", openedAt: 100)
    let service = makeService(archivedEntries: [entry])

    service.deleteArchivedPermanently(entry)

    XCTAssertTrue(service.archivedEntries.isEmpty)
    XCTAssertTrue(service.recentEntries.isEmpty)
  }

  func testUpsertReopeningArchivedFileUnarchivesIt() {
    let entry = makeEntry(path: "/movies/a.mp4", openedAt: 100)
    let service = makeService(archivedEntries: [entry])

    service.upsert(
      for: URL(fileURLWithPath: "/movies/a.mp4"),
      position: 5,
      duration: 100,
      openedAt: Date(timeIntervalSince1970: 200),
      selectedSubtitle: nil
    )

    XCTAssertTrue(service.archivedEntries.isEmpty)
    XCTAssertEqual(service.recentEntries.map(\.filePath), ["/movies/a.mp4"])
  }

  func testLifecycleChangesPersistThroughRepository() {
    let entry = makeEntry(path: "/movies/a.mp4", openedAt: 100)
    let repository = InMemoryRecentLibraryRepository(
      RecentLibraryState(recentEntries: [entry], archivedEntries: [])
    )
    let service = LibraryService(repository: repository)

    service.archive(entry)

    let reloaded = LibraryService(repository: repository)
    XCTAssertTrue(reloaded.recentEntries.isEmpty)
    XCTAssertEqual(reloaded.archivedEntries.map(\.filePath), ["/movies/a.mp4"])
  }

  func testUpsertPrunesToMaxRecentEntriesKeepingMostRecentlyOpened() {
    let service = makeService(maxRecentEntries: 3)

    for index in 1...5 {
      service.upsert(
        for: URL(fileURLWithPath: "/movies/\(index).mp4"),
        position: 0,
        duration: 100,
        openedAt: Date(timeIntervalSince1970: TimeInterval(index)),
        selectedSubtitle: nil
      )
    }

    XCTAssertEqual(service.recentEntries.map(\.filePath), ["/movies/5.mp4", "/movies/4.mp4", "/movies/3.mp4"])
  }

  private func makeService(
    recentEntries: [RecentPlaybackEntry] = [],
    archivedEntries: [RecentPlaybackEntry] = [],
    maxRecentEntries: Int = 50
  ) -> LibraryService {
    let repository = InMemoryRecentLibraryRepository(
      RecentLibraryState(recentEntries: recentEntries, archivedEntries: archivedEntries)
    )
    return LibraryService(repository: repository, maxRecentEntries: maxRecentEntries)
  }

  private func makeEntry(path: String, openedAt: TimeInterval) -> RecentPlaybackEntry {
    RecentPlaybackEntry(
      filePath: path,
      bookmarkData: nil,
      lastPlaybackPosition: 0,
      duration: 100,
      lastOpenedAt: Date(timeIntervalSince1970: openedAt),
      fileSize: nil,
      contentModificationDate: nil,
      selectedSubtitle: nil
    )
  }
}
