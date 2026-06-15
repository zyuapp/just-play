import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PlayerViewModel: ObservableObject {
  @Published var playbackRate: Double = 1.0 {
    didSet {
      engine.setRate(Float(playbackRate))
    }
  }

  @Published var volume: Double = 1.0 {
    didSet {
      engine.setVolume(Float(volume))
    }
  }

  @Published var isMuted = false {
    didSet {
      engine.setMuted(isMuted)
    }
  }

  let engine: PlaybackEngine

  var playbackState: PlaybackState { session.playbackState }
  var currentURL: URL? { session.currentURL }
  var statusMessage: String { session.statusMessage }
  var currentFilePath: String? { session.currentFilePath }

  var recentEntries: [RecentPlaybackEntry] { library.recentEntries }
  var archivedEntries: [RecentPlaybackEntry] { library.archivedEntries }

  var subtitleText: String? { subtitleService.subtitleText }
  var activeSubtitleFileName: String? { subtitleService.activeFileName }
  var subtitleTimelineCues: [SubtitleCue] { subtitleService.timelineCues }
  var activeSubtitleCueIndex: Int? { subtitleService.activeCueIndex }
  var hasSubtitleTrack: Bool { subtitleService.hasTrack }

  var subtitlesEnabled: Bool {
    get { subtitleService.isEnabled }
    set { subtitleService.isEnabled = newValue }
  }

  private let subtitleService: SubtitleService
  private let library: LibraryService
  private let session: PlaybackSessionService
  private var sessionObservation: AnyCancellable?

  init(
    engine: PlaybackEngine = PlaybackEngineFactory.makeDefaultEngine(),
    recentPlaybackStore: RecentLibraryRepository = FileRecentLibraryRepository(),
    enableProgressPersistenceTimer: Bool = true,
    observeApplicationWillTerminate: Bool = true,
    restorePreviousSessionOnLaunch: Bool = true,
    noteRecentDocumentURL: ((URL) -> Void)? = nil
  ) {
    self.engine = engine

    let resolvedNoteRecentDocumentURL = noteRecentDocumentURL ?? { url in
      NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    let subtitleService = SubtitleService(
      parser: SRTSubtitleParser(),
      setNativeRendering: { [engine] enabled in
        engine.setNativeSubtitleRenderingEnabled(enabled)
      }
    )
    self.subtitleService = subtitleService

    let library = LibraryService(repository: recentPlaybackStore)
    self.library = library

    self.session = PlaybackSessionService(
      engine: engine,
      library: library,
      subtitles: subtitleService,
      enableProgressPersistenceTimer: enableProgressPersistenceTimer,
      observeApplicationWillTerminate: observeApplicationWillTerminate,
      restorePreviousSessionOnLaunch: restorePreviousSessionOnLaunch,
      noteRecentDocumentURL: resolvedNoteRecentDocumentURL
    )

    engine.setRate(Float(playbackRate))
    engine.setVolume(Float(volume))
    engine.setMuted(isMuted)

    sessionObservation = session.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
  }

  func open(url: URL, autoplay: Bool = true) {
    session.open(url: url, autoplay: autoplay)
  }

  func openPanel() {
    VideoOpenPanel.present()
  }

  func openRecent(_ entry: RecentPlaybackEntry) {
    session.openRecent(entry)
  }

  func removeRecent(_ entry: RecentPlaybackEntry) {
    session.archiveRecent(entry)
  }

  func restoreArchivedRecent(_ entry: RecentPlaybackEntry) {
    session.restoreArchivedRecent(entry)
  }

  func deleteArchivedRecentPermanently(_ entry: RecentPlaybackEntry) {
    session.deleteArchivedRecentPermanently(entry)
  }

  func selectSubtitleTrack(_ trackID: String) {
    session.selectSubtitleTrack(trackID)
  }

  func openSubtitlePanel() {
    let panel = NSOpenPanel()
    panel.title = "Add Subtitle"
    panel.prompt = "Add"
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = subtitleContentTypes()

    guard panel.runModal() == .OK, let subtitleURL = panel.url else {
      return
    }

    session.loadManualSubtitle(from: subtitleURL)
  }

  func removeSubtitleTrack() {
    session.removeSubtitleTrack()
  }

  func seekToSubtitleCue(at index: Int) {
    session.seekToSubtitleCue(at: index)
  }

  func togglePlayPause() {
    session.togglePlayPause()
  }

  func skipForward() {
    session.skipForward()
  }

  func skipBackward() {
    session.skipBackward()
  }

  func seek(to seconds: Double, persistImmediately: Bool = false) {
    session.seek(to: seconds, persistImmediately: persistImmediately)
  }

  private func subtitleContentTypes() -> [UTType] {
    if let srtType = UTType(filenameExtension: "srt") {
      return [srtType, .plainText]
    }

    return [.plainText]
  }
}
