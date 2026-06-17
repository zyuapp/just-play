import XCTest
@testable import JustPlay

@MainActor
final class SubtitleServiceTests: XCTestCase {
  private final class NativeRenderingRecorder {
    var values: [Bool] = []
  }

  func testLoadManualSubtitleActivatesTrackAndAnnounces() {
    let parser = StubSubtitleParser(result: .success([cue(0, 2, "Hello"), cue(3, 4, "World")]))
    let (service, recorder) = makeService(parser: parser)
    var announcements: [String] = []
    var selectionChanges = 0
    service.announce = { announcements.append($0) }
    service.onSelectionChanged = { selectionChanges += 1 }

    service.loadManualSubtitle(from: URL(fileURLWithPath: "/tmp/movie.srt"))

    XCTAssertTrue(service.hasTrack)
    XCTAssertEqual(service.timelineCues.count, 2)
    XCTAssertEqual(service.activeFileName, "movie.srt")
    XCTAssertTrue(service.isEnabled)
    XCTAssertEqual(recorder.values.last, false)
    XCTAssertEqual(announcements, ["Loaded subtitle: movie.srt"])
    XCTAssertEqual(selectionChanges, 1)
  }

  func testLoadEmptyTrackAnnouncesFailure() {
    let parser = StubSubtitleParser(result: .success([]))
    let (service, _) = makeService(parser: parser)
    var announcements: [String] = []
    service.announce = { announcements.append($0) }

    service.loadManualSubtitle(from: URL(fileURLWithPath: "/tmp/empty.srt"))

    XCTAssertFalse(service.hasTrack)
    XCTAssertEqual(announcements, ["Unable to read subtitle file."])
  }

  func testUpdateTextResolvesActiveCue() {
    let parser = StubSubtitleParser(result: .success([cue(0, 2, "A"), cue(5, 7, "B")]))
    let (service, _) = makeService(parser: parser)
    service.loadManualSubtitle(from: URL(fileURLWithPath: "/tmp/m.srt"))

    service.updateText(for: 6)
    XCTAssertEqual(service.activeCueIndex, 1)
    XCTAssertEqual(service.subtitleText, "B")

    service.updateText(for: 3)
    XCTAssertNil(service.activeCueIndex)
    XCTAssertNil(service.subtitleText)
  }

  func testDisablingHidesTextButStillComputesCueIndex() {
    let parser = StubSubtitleParser(result: .success([cue(0, 2, "A")]))
    let (service, _) = makeService(parser: parser)
    service.loadManualSubtitle(from: URL(fileURLWithPath: "/tmp/m.srt"))
    service.updateText(for: 1)
    XCTAssertEqual(service.subtitleText, "A")

    service.isEnabled = false
    XCTAssertNil(service.subtitleText)
    XCTAssertEqual(service.activeCueIndex, 0)

    service.isEnabled = true
    XCTAssertEqual(service.subtitleText, "A")
  }

  func testRemoveSelectedTrackClearsAndRestoresNativeRendering() {
    let parser = StubSubtitleParser(result: .success([cue(0, 2, "A")]))
    let (service, recorder) = makeService(parser: parser)
    service.loadManualSubtitle(from: URL(fileURLWithPath: "/tmp/m.srt"))
    XCTAssertTrue(service.hasTrack)

    service.removeSelectedTrack()

    XCTAssertFalse(service.hasTrack)
    XCTAssertNil(service.subtitleText)
    XCTAssertTrue(service.timelineCues.isEmpty)
    XCTAssertEqual(recorder.values.last, true)
  }

  func testResetForNewVideoClearsTrack() {
    let parser = StubSubtitleParser(result: .success([cue(0, 2, "A")]))
    let (service, _) = makeService(parser: parser)
    service.loadManualSubtitle(from: URL(fileURLWithPath: "/tmp/m.srt"))

    service.resetForNewVideo()

    XCTAssertFalse(service.hasTrack)
    XCTAssertTrue(service.timelineCues.isEmpty)
  }

  func testCurrentSelectionReflectsActiveTrack() {
    let parser = StubSubtitleParser(result: .success([cue(0, 2, "A")]))
    let (service, _) = makeService(parser: parser)
    service.loadManualSubtitle(from: URL(fileURLWithPath: "/tmp/Subs/m.srt"))

    let selection = service.currentSelection()
    XCTAssertEqual(selection?.displayName, "m.srt")
    XCTAssertEqual(selection?.source, .manual)
  }

  func testCueStartReturnsCueStartOrNil() {
    let parser = StubSubtitleParser(result: .success([cue(0, 2, "A"), cue(5, 7, "B")]))
    let (service, _) = makeService(parser: parser)
    service.loadManualSubtitle(from: URL(fileURLWithPath: "/tmp/m.srt"))

    XCTAssertEqual(service.cueStart(at: 1), 5)
    XCTAssertNil(service.cueStart(at: 9))
  }

  func testRestoreLoadsSelectionWhenFileExists() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SubtitleServiceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let subtitleURL = directory.appendingPathComponent("video.srt")
    try Data("ignored".utf8).write(to: subtitleURL)

    let parser = StubSubtitleParser(result: .success([cue(0, 2, "A")]))
    let (service, _) = makeService(parser: parser)
    let selection = RecentPlaybackEntry.SubtitleSelection(
      filePath: subtitleURL.path,
      bookmarkData: nil,
      displayName: "video.srt",
      source: .autoDetected
    )

    service.restore(selection: selection)

    XCTAssertTrue(service.hasTrack)
    XCTAssertEqual(service.activeFileName, "video.srt")
  }

  func testRestoreSkipsMissingFile() {
    let parser = StubSubtitleParser(result: .success([cue(0, 2, "A")]))
    let (service, _) = makeService(parser: parser)
    let selection = RecentPlaybackEntry.SubtitleSelection(
      filePath: "/nonexistent/missing.srt",
      bookmarkData: nil,
      displayName: "missing.srt",
      source: .manual
    )

    service.restore(selection: selection)

    XCTAssertFalse(service.hasTrack)
  }

  private func cue(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> SubtitleCue {
    SubtitleCue(start: start, end: end, text: text)
  }

  private func makeService(parser: SubtitleParser) -> (SubtitleService, NativeRenderingRecorder) {
    let recorder = NativeRenderingRecorder()
    let service = SubtitleService(parser: parser) { recorder.values.append($0) }
    return (service, recorder)
  }
}
