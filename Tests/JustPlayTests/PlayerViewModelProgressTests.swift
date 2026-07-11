import Foundation
import XCTest
@testable import JustPlay

@MainActor
final class PlayerViewModelProgressTests: XCTestCase {
  private var cleanupURLs: [URL] = []

  override func tearDown() {
    let fileManager = FileManager.default

    for url in cleanupURLs {
      try? fileManager.removeItem(at: url)
    }

    cleanupURLs.removeAll()
    super.tearDown()
  }

  func testResumeSeekIsAppliedWhenSavedProgressIsValid() async throws {
    let videoURL = try makeVideoFile(named: "resume-valid")
    let store = makeStore()
    seedState(
      in: store,
      recentEntries: [
        makeEntry(url: videoURL, position: 120, duration: 300)
      ]
    )

    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL, autoplay: true)
    XCTAssertTrue(viewModel.statusMessage.contains("(resuming)"))

    engine.emitState(playbackState(isPlaying: true, currentTime: 0, duration: 300))
    await drainMainActorTasks()

    XCTAssertTrue(engine.events.contains { event in
      guard case let .seek(time) = event else {
        return false
      }

      return abs(time - 120) < 0.001
    })
    XCTAssertEqual(viewModel.playbackState.currentTime, 120, accuracy: 0.001)
  }

  func testResumeSeekIsSkippedForNearCompleteProgress() async throws {
    let videoURL = try makeVideoFile(named: "resume-near-end")
    let store = makeStore()
    seedState(
      in: store,
      recentEntries: [
        makeEntry(url: videoURL, position: 294, duration: 300)
      ]
    )

    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: true, currentTime: 0, duration: 300))
    await drainMainActorTasks()

    XCTAssertFalse(viewModel.statusMessage.contains("(resuming)"))
    XCTAssertFalse(engine.events.contains { event in
      if case .seek = event {
        return true
      }

      return false
    })
  }

  func testSkipActionsPersistImmediatelyAndClampToDuration() async throws {
    let videoURL = try makeVideoFile(named: "skip-clamp")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: true, currentTime: 95, duration: 100))
    await drainMainActorTasks()

    viewModel.skipForward()
    XCTAssertEqual(entry(for: videoURL, in: viewModel.recentEntries)?.lastPlaybackPosition ?? -1, 100, accuracy: 0.001)

    viewModel.skipBackward()
    XCTAssertEqual(entry(for: videoURL, in: viewModel.recentEntries)?.lastPlaybackPosition ?? -1, 85, accuracy: 0.001)

    XCTAssertTrue(engine.events.contains(.skip(10)))
    XCTAssertTrue(engine.events.contains(.skip(-10)))
  }

  func testPlaybackFinishClearsResumePosition() async throws {
    let videoURL = try makeVideoFile(named: "finish-clears")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: true, currentTime: 80, duration: 200))
    await drainMainActorTasks()

    viewModel.seek(to: 80, persistImmediately: true)
    XCTAssertEqual(entry(for: videoURL, in: viewModel.recentEntries)?.lastPlaybackPosition ?? -1, 80, accuracy: 0.001)

    engine.emitPlaybackDidFinish()
    await drainMainActorTasks()

    XCTAssertEqual(entry(for: videoURL, in: viewModel.recentEntries)?.lastPlaybackPosition ?? -1, 0, accuracy: 0.001)
  }

  func testPausedSeekKeepsRequestedTimeUntilEngineConfirms() async throws {
    let videoURL = try makeVideoFile(named: "paused-seek")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: false, currentTime: 0, duration: 200))
    await drainMainActorTasks()

    viewModel.seek(to: 60)
    XCTAssertEqual(viewModel.playbackState.currentTime, 60, accuracy: 0.001)

    engine.emitState(playbackState(isPlaying: false, currentTime: 10, duration: 200))
    await drainMainActorTasks()
    XCTAssertEqual(viewModel.playbackState.currentTime, 60, accuracy: 0.001)

    engine.emitState(playbackState(isPlaying: false, currentTime: 60.2, duration: 200))
    await drainMainActorTasks()
    XCTAssertEqual(viewModel.playbackState.currentTime, 60.2, accuracy: 0.001)

    engine.emitState(playbackState(isPlaying: false, currentTime: 20, duration: 200))
    await drainMainActorTasks()
    XCTAssertEqual(viewModel.playbackState.currentTime, 20, accuracy: 0.001)
  }

  func testSeekDiscardsPlaybackStateCapturedBeforeRequest() async throws {
    let videoURL = try makeVideoFile(named: "stale-state-after-seek")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: true, currentTime: 10, duration: 200))

    viewModel.seek(to: 60)
    await drainMainActorTasks()

    XCTAssertEqual(viewModel.playbackState.currentTime, 60, accuracy: 0.001)
  }

  func testSeekPositionStaysPinnedWhenPlaybackResumesBeforeSeekConfirmation() async throws {
    let videoURL = try makeVideoFile(named: "resume-before-seek-confirmation")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: false, currentTime: 10, duration: 200))
    await drainMainActorTasks()

    viewModel.seek(to: 60)
    viewModel.play()
    engine.emitState(playbackState(isPlaying: true, currentTime: 10, duration: 200))
    await drainMainActorTasks()
    XCTAssertEqual(viewModel.playbackState.currentTime, 60, accuracy: 0.001)

    engine.emitState(playbackState(isPlaying: true, currentTime: 60.2, duration: 200))
    await drainMainActorTasks()
    XCTAssertEqual(viewModel.playbackState.currentTime, 60.2, accuracy: 0.001)
  }

  func testFinishSeekingResumesOnlyAfterAsynchronousSeekCompletes() async throws {
    let videoURL = try makeVideoFile(named: "resume-after-seek-completion")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    engine.completesSeeksImmediately = false
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: false, currentTime: 10, duration: 200))
    await drainMainActorTasks()

    _ = viewModel.beginSeeking()
    viewModel.finishSeeking(to: 60)
    XCTAssertFalse(engine.events.contains(.play))

    engine.completeNextSeek()
    await drainMainActorTasks()
    XCTAssertTrue(engine.events.contains(.play))
  }

  func testSeekingResumesWhenPlaybackStateIsTemporarilyNotPlaying() async throws {
    let videoURL = try makeVideoFile(named: "seek-while-buffering")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL, autoplay: true)
    engine.emitState(playbackState(isPlaying: false, currentTime: 10, duration: 200))
    await drainMainActorTasks()

    let shouldResumePlayback = viewModel.beginSeeking()
    XCTAssertTrue(shouldResumePlayback)
    XCTAssertTrue(engine.events.contains(.pause))

    viewModel.finishSeeking(to: 60)
    await drainMainActorTasks()
    XCTAssertTrue(engine.events.contains(.play))
  }

  func testSeekingDoesNotResumeWhenPlaybackWasPaused() async throws {
    let videoURL = try makeVideoFile(named: "seek-while-paused")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL, autoplay: false)
    engine.emitState(playbackState(isPlaying: false, currentTime: 10, duration: 200))
    await drainMainActorTasks()

    let shouldResumePlayback = viewModel.beginSeeking()
    XCTAssertFalse(shouldResumePlayback)

    viewModel.finishSeeking(to: 60)
    await drainMainActorTasks()
    XCTAssertFalse(engine.events.contains(.play))
  }

  func testSupersededSeekCompletionDoesNotResumePlayback() async throws {
    let videoURL = try makeVideoFile(named: "superseded-seek-completion")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    engine.completesSeeksImmediately = false
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL, autoplay: true)
    engine.emitState(playbackState(isPlaying: false, currentTime: 10, duration: 200))
    await drainMainActorTasks()

    _ = viewModel.beginSeeking()
    viewModel.finishSeeking(to: 60)
    _ = viewModel.beginSeeking()
    viewModel.finishSeeking(to: 90)

    engine.completeNextSeek()
    await drainMainActorTasks()
    XCTAssertFalse(engine.events.contains(.play))

    engine.completeNextSeek()
    await drainMainActorTasks()
    XCTAssertTrue(engine.events.contains(.play))
  }

  func testCompletedSeekDoesNotResumeReplacementMedia() async throws {
    let firstURL = try makeVideoFile(named: "completed-seek-original")
    let replacementURL = try makeVideoFile(named: "completed-seek-replacement")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: firstURL, autoplay: true)
    engine.emitState(playbackState(isPlaying: false, currentTime: 10, duration: 200))
    await drainMainActorTasks()

    _ = viewModel.beginSeeking()
    viewModel.finishSeeking(to: 60)
    viewModel.open(url: replacementURL, autoplay: false)
    await drainMainActorTasks()

    XCTAssertFalse(engine.events.contains(.play))
  }

  func testStalePlaybackFinishDoesNotClearReplacementProgress() async throws {
    let firstURL = try makeVideoFile(named: "finished-original")
    let replacementURL = try makeVideoFile(named: "finished-replacement")
    let store = makeStore()
    seedState(
      in: store,
      recentEntries: [makeEntry(url: replacementURL, position: 50, duration: 200)]
    )
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: firstURL)
    engine.emitPlaybackDidFinish()
    viewModel.open(url: replacementURL, autoplay: false)
    await drainMainActorTasks()

    XCTAssertEqual(
      entry(for: replacementURL, in: viewModel.recentEntries)?.lastPlaybackPosition ?? -1,
      50,
      accuracy: 0.001
    )
  }

  func testLaunchRestoresMostRecentSessionWithoutAutoplay() async throws {
    let videoURL = try makeVideoFile(named: "restore-launch")
    let store = makeStore()
    seedState(
      in: store,
      recentEntries: [
        makeEntry(url: videoURL, position: 42, duration: 120)
      ]
    )

    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: true)
    _ = viewModel

    XCTAssertTrue(engine.events.contains(.load(path: videoURL.path, autoplay: false)))

    engine.emitState(playbackState(isPlaying: false, currentTime: 0, duration: 120))
    await drainMainActorTasks()

    XCTAssertTrue(engine.events.contains { event in
      guard case let .seek(time) = event else {
        return false
      }

      return abs(time - 42) < 0.001
    })
    XCTAssertTrue(engine.events.contains(.play))

    engine.emitState(playbackState(isPlaying: true, currentTime: 42, duration: 120))
    await drainMainActorTasks()
    XCTAssertTrue(engine.events.contains(.pause))
  }

  func testArchivingCurrentlyPlayingFileIsIgnored() async throws {
    let videoURL = try makeVideoFile(named: "archive-current")
    let store = makeStore()
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: videoURL)
    engine.emitState(playbackState(isPlaying: true, currentTime: 5, duration: 100))
    await drainMainActorTasks()

    let current = try XCTUnwrap(entry(for: videoURL, in: viewModel.recentEntries))
    viewModel.removeRecent(current)

    XCTAssertNotNil(entry(for: videoURL, in: viewModel.recentEntries))
    XCTAssertTrue(viewModel.archivedEntries.isEmpty)
  }

  func testArchivingNonPlayingFileMovesItToArchived() async throws {
    let playingURL = try makeVideoFile(named: "archive-keep")
    let otherURL = try makeVideoFile(named: "archive-move")
    let store = makeStore()
    seedState(in: store, recentEntries: [makeEntry(url: otherURL, position: 10, duration: 100)])
    let engine = TestPlaybackEngine()
    let viewModel = makeViewModel(engine: engine, store: store, restorePreviousSessionOnLaunch: false)

    viewModel.open(url: playingURL)
    engine.emitState(playbackState(isPlaying: true, currentTime: 5, duration: 100))
    await drainMainActorTasks()

    let other = try XCTUnwrap(entry(for: otherURL, in: viewModel.recentEntries))
    viewModel.removeRecent(other)

    XCTAssertNil(entry(for: otherURL, in: viewModel.recentEntries))
    XCTAssertEqual(viewModel.archivedEntries.map(\.filePath), [otherURL.standardizedFileURL.path])
  }

  private func makeViewModel(
    engine: TestPlaybackEngine,
    store: InMemoryRecentLibraryRepository,
    restorePreviousSessionOnLaunch: Bool
  ) -> PlayerViewModel {
    PlayerViewModel(
      engine: engine,
      recentPlaybackStore: store,
      enableProgressPersistenceTimer: false,
      observeApplicationWillTerminate: false,
      restorePreviousSessionOnLaunch: restorePreviousSessionOnLaunch,
      noteRecentDocumentURL: { _ in }
    )
  }

  private func playbackState(isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) -> PlaybackState {
    PlaybackState(
      isPlaying: isPlaying,
      currentTime: currentTime,
      duration: duration,
      rate: 1.0,
      volume: 1.0,
      isMuted: false
    )
  }

  private func entry(for url: URL, in entries: [RecentPlaybackEntry]) -> RecentPlaybackEntry? {
    let normalizedPath = url.standardizedFileURL.path
    return entries.first { $0.filePath == normalizedPath }
  }

  private func makeStore() -> InMemoryRecentLibraryRepository {
    InMemoryRecentLibraryRepository()
  }

  private func seedState(in store: InMemoryRecentLibraryRepository, recentEntries: [RecentPlaybackEntry]) {
    store.saveState(.init(recentEntries: recentEntries, archivedEntries: []))
  }

  private func makeEntry(url: URL, position: TimeInterval, duration: TimeInterval) -> RecentPlaybackEntry {
    RecentPlaybackEntry(
      filePath: url.standardizedFileURL.path,
      bookmarkData: nil,
      lastPlaybackPosition: position,
      duration: duration,
      lastOpenedAt: Date(),
      fileSize: nil,
      contentModificationDate: nil,
      selectedSubtitle: nil
    )
  }

  private func makeVideoFile(named baseName: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("JustPlayTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    cleanupURLs.append(directoryURL)

    let fileURL = directoryURL.appendingPathComponent(baseName).appendingPathExtension("mp4")
    let created = FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
    XCTAssertTrue(created)
    return fileURL
  }

  private func drainMainActorTasks() async {
    for _ in 0..<10 {
      await Task.yield()
    }
  }
}
