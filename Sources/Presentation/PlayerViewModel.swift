import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PlayerViewModel: ObservableObject {
  @Published private(set) var playbackState: PlaybackState = .initial
  @Published private(set) var currentURL: URL?
  @Published private(set) var statusMessage = "Drop an MP4 or MKV file, or open one from the menu."
  @Published private(set) var recentEntries: [RecentPlaybackEntry]
  @Published private(set) var archivedEntries: [RecentPlaybackEntry]

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

  var currentFilePath: String? {
    currentURL.map(RecentPlaybackEntry.normalizedPath(for:))
  }

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
  private let recentPlaybackStore: RecentLibraryRepository
  private let noteRecentDocumentURL: (URL) -> Void
  private let supportedFileExtensions = Set(["mp4", "m4v", "mkv"])
  private let maxRecentEntries = 50
  private let resumePolicy = ResumePolicy()

  private var resumeCoordinator = ResumeCoordinator()
  private var currentOpenedAt = Date()
  private var subtitleObservation: AnyCancellable?

  private var playbackProgressTimer: Timer?
  private var appWillTerminateObserver: NSObjectProtocol?

  init(
    engine: PlaybackEngine = PlaybackEngineFactory.makeDefaultEngine(),
    recentPlaybackStore: RecentLibraryRepository = FileRecentLibraryRepository(),
    enableProgressPersistenceTimer: Bool = true,
    observeApplicationWillTerminate: Bool = true,
    restorePreviousSessionOnLaunch: Bool = true,
    noteRecentDocumentURL: ((URL) -> Void)? = nil
  ) {
    self.engine = engine
    self.recentPlaybackStore = recentPlaybackStore
    self.noteRecentDocumentURL = noteRecentDocumentURL ?? { url in
      NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    let storedState = recentPlaybackStore.loadState()
    recentEntries = storedState.recentEntries
    archivedEntries = storedState.archivedEntries

    self.subtitleService = SubtitleService(
      parser: SRTSubtitleParser(),
      setNativeRendering: { [engine] enabled in
        engine.setNativeSubtitleRenderingEnabled(enabled)
      }
    )

    subtitleService.onSelectionChanged = { [weak self] in
      self?.persistCurrentPlaybackProgress(force: true)
    }

    subtitleService.announce = { [weak self] message in
      self?.statusMessage = message
    }

    subtitleObservation = subtitleService.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }

    self.engine.stateDidChange = { [weak self] state in
      Task { @MainActor in
        self?.handlePlaybackStateChange(state)
      }
    }

    self.engine.playbackDidFinish = { [weak self] in
      Task { @MainActor in
        self?.handlePlaybackDidFinish()
      }
    }

    self.engine.setRate(Float(playbackRate))
    self.engine.setVolume(Float(volume))
    self.engine.setMuted(isMuted)
    self.engine.setNativeSubtitleRenderingEnabled(true)

    if enableProgressPersistenceTimer {
      startPlaybackProgressTimer()
    }

    if observeApplicationWillTerminate {
      appWillTerminateObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.persistCurrentPlaybackProgress(force: true)
        }
      }
    }

    if restorePreviousSessionOnLaunch {
      restoreMostRecentPlaybackSessionIfAvailable()
    }
  }

  deinit {
    playbackProgressTimer?.invalidate()

    if let appWillTerminateObserver {
      NotificationCenter.default.removeObserver(appWillTerminateObserver)
    }
  }

  func open(url: URL, autoplay: Bool = true) {
    let normalizedURL = url.standardizedFileURL

    guard isSupported(url: normalizedURL) else {
      statusMessage = "Unsupported file type: .\(url.pathExtension.lowercased())"
      return
    }

    currentURL = normalizedURL
    currentOpenedAt = Date()

    let resumePosition = resumePosition(for: normalizedURL)
    resumeCoordinator.beginResume(toPosition: resumePosition, autoplay: autoplay)

    if resumePosition != nil {
      statusMessage = "\(normalizedURL.lastPathComponent) (resuming)"
    } else {
      statusMessage = normalizedURL.lastPathComponent
    }

    subtitleService.resetForNewVideo()
    subtitleService.loadAutoDetectedSubtitle(for: normalizedURL)
    subtitleService.restore(selection: existingEntry(for: normalizedURL)?.selectedSubtitle)

    engine.load(url: normalizedURL, autoplay: autoplay)
    noteRecentDocumentURL(normalizedURL)

    let seedDuration = existingEntry(for: normalizedURL)?.duration ?? 0
    upsertRecentEntry(
      for: normalizedURL,
      position: resumePosition ?? 0,
      duration: seedDuration,
      openedAt: currentOpenedAt
    )
  }

  func openPanel() {
    VideoOpenPanel.present()
  }

  func openRecent(_ entry: RecentPlaybackEntry) {
    open(url: entry.resolvedURL)
  }

  func removeRecent(_ entry: RecentPlaybackEntry) {
    guard entry.filePath != currentFilePath else {
      return
    }

    recentEntries.removeAll { $0.filePath == entry.filePath }
    archivedEntries.removeAll { $0.filePath == entry.filePath }
    archivedEntries.append(entry)
    archivedEntries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    saveRecentsState()
  }

  func restoreArchivedRecent(_ entry: RecentPlaybackEntry) {
    archivedEntries.removeAll { $0.filePath == entry.filePath }
    recentEntries.removeAll { $0.filePath == entry.filePath }
    recentEntries.append(entry)
    recentEntries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    saveRecentsState()
  }

  func deleteArchivedRecentPermanently(_ entry: RecentPlaybackEntry) {
    archivedEntries.removeAll { $0.filePath == entry.filePath }
    saveRecentsState()
  }

  func selectSubtitleTrack(_ trackID: String) {
    subtitleService.selectTrack(trackID)
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

    subtitleService.loadManualSubtitle(from: subtitleURL)
  }

  func removeSubtitleTrack() {
    subtitleService.removeSelectedTrack()
  }

  func seekToSubtitleCue(at index: Int) {
    guard let start = subtitleService.cueStart(at: index) else {
      return
    }

    seek(to: start, persistImmediately: true)
  }

  func togglePlayPause() {
    if playbackState.isPlaying {
      engine.pause()
    } else {
      engine.play()
    }
  }

  func skipForward() {
    skip(by: 10)
  }

  func skipBackward() {
    skip(by: -10)
  }

  func seek(to seconds: Double, persistImmediately: Bool = false) {
    let clampedSeconds: TimeInterval
    if playbackState.duration > 0 {
      clampedSeconds = min(max(seconds, 0), playbackState.duration)
    } else {
      clampedSeconds = max(seconds, 0)
    }

    resumeCoordinator.userDidSeek(to: clampedSeconds, isPlaying: playbackState.isPlaying)

    engine.seek(to: clampedSeconds)
    playbackState.currentTime = clampedSeconds
    subtitleService.updateText(for: clampedSeconds)

    if persistImmediately {
      persistCurrentPlaybackProgress(force: true, overridePosition: clampedSeconds)
    }
  }

  private func isSupported(url: URL) -> Bool {
    supportedFileExtensions.contains(url.pathExtension.lowercased())
  }

  private func restoreMostRecentPlaybackSessionIfAvailable() {
    guard let entry = recentEntries.first else {
      return
    }

    let url = entry.resolvedURL.standardizedFileURL
    guard
      FileManager.default.fileExists(atPath: url.path),
      isSupported(url: url)
    else {
      return
    }

    open(url: url, autoplay: false)
  }

  private func handlePlaybackStateChange(_ state: PlaybackState) {
    let resolution = resumeCoordinator.reconcile(with: state)

    var resolvedState = state
    resolvedState.currentTime = resolution.displayTime
    playbackState = resolvedState

    apply(resolution.actions)
    subtitleService.updateText(for: playbackState.currentTime)
  }

  private func apply(_ actions: [ResumeCoordinator.Action]) {
    for action in actions {
      switch action {
      case let .seek(time):
        engine.seek(to: time)
      case .play:
        engine.play()
      case .pause:
        engine.pause()
      }
    }
  }

  private func handlePlaybackDidFinish() {
    clearResumePositionForCurrentFile()
  }

  private func startPlaybackProgressTimer() {
    let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.persistCurrentPlaybackProgress()
      }
    }

    RunLoop.main.add(timer, forMode: .common)
    playbackProgressTimer = timer
  }

  private func skip(by interval: TimeInterval) {
    let projectedPosition = playbackState.currentTime + interval
    engine.skip(by: interval)
    persistCurrentPlaybackProgress(force: true, overridePosition: projectedPosition)
  }

  private func persistCurrentPlaybackProgress(force: Bool = false, overridePosition: TimeInterval? = nil) {
    guard let currentURL else {
      return
    }

    let duration = max(playbackState.duration, existingEntry(for: currentURL)?.duration ?? 0)
    let currentTime = max(overridePosition ?? playbackState.currentTime, 0)

    if duration <= 0 && !force {
      return
    }

    upsertRecentEntry(
      for: currentURL,
      position: currentTime,
      duration: duration,
      openedAt: currentOpenedAt
    )
  }

  private func clearResumePositionForCurrentFile() {
    guard let currentURL else {
      return
    }

    let duration = max(playbackState.duration, existingEntry(for: currentURL)?.duration ?? 0)

    upsertRecentEntry(
      for: currentURL,
      position: 0,
      duration: duration,
      openedAt: currentOpenedAt
    )
  }

  private func upsertRecentEntry(
    for url: URL,
    position: TimeInterval,
    duration: TimeInterval,
    openedAt: Date
  ) {
    let normalizedPath = RecentPlaybackEntry.normalizedPath(for: url)
    let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

    let bookmarkData = try? url.bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    let clampedDuration = max(duration, 0)
    let clampedPosition: TimeInterval
    if clampedDuration > 0 {
      clampedPosition = min(max(position, 0), clampedDuration)
    } else {
      clampedPosition = max(position, 0)
    }

    let selectedSubtitle = subtitleService.currentSelection()

    if let index = recentEntries.firstIndex(where: { $0.filePath == normalizedPath }) {
      var existing = recentEntries[index]
      existing.bookmarkData = bookmarkData ?? existing.bookmarkData
      existing.lastPlaybackPosition = clampedPosition
      existing.duration = max(existing.duration, clampedDuration)
      existing.lastOpenedAt = openedAt
      existing.fileSize = resourceValues?.fileSize.map(Int64.init) ?? existing.fileSize
      existing.contentModificationDate = resourceValues?.contentModificationDate ?? existing.contentModificationDate
      existing.selectedSubtitle = selectedSubtitle
      recentEntries[index] = existing
    } else {
      let entry = RecentPlaybackEntry(
        filePath: normalizedPath,
        bookmarkData: bookmarkData,
        lastPlaybackPosition: clampedPosition,
        duration: clampedDuration,
        lastOpenedAt: openedAt,
        fileSize: resourceValues?.fileSize.map(Int64.init),
        contentModificationDate: resourceValues?.contentModificationDate,
        selectedSubtitle: selectedSubtitle
      )
      recentEntries.append(entry)
    }

    recentEntries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    if recentEntries.count > maxRecentEntries {
      recentEntries = Array(recentEntries.prefix(maxRecentEntries))
    }

    archivedEntries.removeAll { $0.filePath == normalizedPath }
    saveRecentsState()
  }

  private func saveRecentsState() {
    let state = RecentLibraryState(
      recentEntries: recentEntries,
      archivedEntries: archivedEntries
    )
    recentPlaybackStore.saveState(state)
  }

  private func existingEntry(for url: URL) -> RecentPlaybackEntry? {
    let normalizedPath = RecentPlaybackEntry.normalizedPath(for: url)
    return recentEntries.first { $0.filePath == normalizedPath }
  }

  private func resumePosition(for url: URL) -> TimeInterval? {
    existingEntry(for: url)?.resumePoint(using: resumePolicy)?.seconds
  }

  private func subtitleContentTypes() -> [UTType] {
    if let srtType = UTType(filenameExtension: "srt") {
      return [srtType, .plainText]
    }

    return [.plainText]
  }

}
