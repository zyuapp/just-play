import Combine
import Foundation

@MainActor
final class PlaybackSessionService: ObservableObject {
  @Published private(set) var playbackState: PlaybackState = .initial
  @Published private(set) var currentURL: URL?
  @Published private(set) var statusMessage = "Drop an MP4 or MKV file, or open one from the menu."

  let engine: PlaybackEngine
  let library: LibraryService
  let subtitles: SubtitleService

  var currentFilePath: String? {
    currentURL.map(RecentPlaybackEntry.normalizedPath(for:))
  }

  private let noteRecentDocumentURL: (URL) -> Void
  private let supportedFileExtensions = Set(["mp4", "m4v", "mkv"])

  private var resumeCoordinator = ResumeCoordinator()
  private var currentOpenedAt = Date()
  private var observations: Set<AnyCancellable> = []
  private var playbackProgressTimer: Timer?
  private let playbackStateGate = PlaybackStateDeliveryGate()
  private var playbackRequested = false
  private var seekShouldResumePlayback: Bool?

  init(
    engine: PlaybackEngine,
    library: LibraryService,
    subtitles: SubtitleService,
    enableProgressPersistenceTimer: Bool = true,
    restorePreviousSessionOnLaunch: Bool = true,
    noteRecentDocumentURL: @escaping (URL) -> Void
  ) {
    self.engine = engine
    self.library = library
    self.subtitles = subtitles
    self.noteRecentDocumentURL = noteRecentDocumentURL

    subtitles.onSelectionChanged = { [weak self] in
      self?.persistCurrentPlaybackProgress(force: true)
    }

    subtitles.announce = { [weak self] message in
      self?.statusMessage = message
    }

    library.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &observations)

    subtitles.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &observations)

    engine.stateDidChange = { [weak self, playbackStateGate] state in
      let token = playbackStateGate.makeToken()

      Task { @MainActor in
        guard playbackStateGate.accepts(token) else {
          return
        }

        self?.handlePlaybackStateChange(state)
      }
    }

    engine.playbackDidFinish = { [weak self, playbackStateGate] in
      let generation = playbackStateGate.currentGeneration()

      Task { @MainActor in
        guard playbackStateGate.isCurrentGeneration(generation) else {
          return
        }

        self?.handlePlaybackDidFinish()
      }
    }

    engine.setNativeSubtitleRenderingEnabled(true)

    if enableProgressPersistenceTimer {
      startPlaybackProgressTimer()
    }

    if restorePreviousSessionOnLaunch {
      restoreMostRecentPlaybackSessionIfAvailable()
    }
  }

  deinit {
    playbackProgressTimer?.invalidate()
  }

  func open(url: URL, autoplay: Bool = true) {
    let normalizedURL = url.standardizedFileURL

    guard isSupported(url: normalizedURL) else {
      statusMessage = "Unsupported file type: .\(url.pathExtension.lowercased())"
      return
    }

    currentURL = normalizedURL
    currentOpenedAt = Date()
    playbackRequested = autoplay
    seekShouldResumePlayback = nil

    let resumePosition = library.resumePosition(for: normalizedURL)
    resumeCoordinator.beginResume(toPosition: resumePosition, autoplay: autoplay)

    if resumePosition != nil {
      statusMessage = "\(normalizedURL.lastPathComponent) (resuming)"
    } else {
      statusMessage = normalizedURL.lastPathComponent
    }

    subtitles.resetForNewVideo()
    subtitles.loadAutoDetectedSubtitle(for: normalizedURL)
    subtitles.restore(selection: library.entry(for: normalizedURL)?.selectedSubtitle)

    performEngineCommand {
      engine.load(url: normalizedURL, autoplay: autoplay)
    }
    noteRecentDocumentURL(normalizedURL)

    let seedDuration = library.entry(for: normalizedURL)?.duration ?? 0
    library.upsert(
      for: normalizedURL,
      position: resumePosition ?? 0,
      duration: seedDuration,
      openedAt: currentOpenedAt,
      selectedSubtitle: subtitles.currentSelection()
    )
  }

  func openRecent(_ entry: RecentPlaybackEntry) {
    open(url: entry.resolvedURL)
  }

  func archiveRecent(_ entry: RecentPlaybackEntry) {
    guard entry.filePath != currentFilePath else {
      return
    }

    library.archive(entry)
  }

  func restoreArchivedRecent(_ entry: RecentPlaybackEntry) {
    library.restoreArchived(entry)
  }

  func deleteArchivedRecentPermanently(_ entry: RecentPlaybackEntry) {
    library.deleteArchivedPermanently(entry)
  }

  func loadManualSubtitle(from url: URL) {
    subtitles.loadManualSubtitle(from: url)
  }

  func selectSubtitleTrack(_ trackID: String) {
    subtitles.selectTrack(trackID)
  }

  func removeSubtitleTrack() {
    subtitles.removeSelectedTrack()
  }

  func seekToSubtitleCue(at index: Int) {
    guard let start = subtitles.cueStart(at: index) else {
      return
    }

    seek(to: start, persistImmediately: true)
  }

  func togglePlayPause() {
    if playbackRequested {
      pause()
    } else {
      play()
    }
  }

  func play() {
    playbackRequested = true
    if seekShouldResumePlayback != nil {
      seekShouldResumePlayback = true
    }
    performEngineCommand(engine.play)
  }

  func pause() {
    playbackRequested = false
    if seekShouldResumePlayback != nil {
      seekShouldResumePlayback = false
    }
    performEngineCommand(engine.pause)
  }

  func beginSeeking() -> Bool {
    if let seekShouldResumePlayback {
      return seekShouldResumePlayback
    }

    let shouldResumePlayback = playbackRequested
    seekShouldResumePlayback = shouldResumePlayback

    if shouldResumePlayback {
      performEngineCommand(engine.pause)
    }

    return shouldResumePlayback
  }

  func skipForward() {
    skip(by: 10)
  }

  func skipBackward() {
    skip(by: -10)
  }

  func seek(to seconds: Double, persistImmediately: Bool = false) {
    let clampedSeconds = prepareSeek(to: seconds)

    performEngineCommand {
      engine.seek(to: clampedSeconds)
    }

    if persistImmediately {
      persistCurrentPlaybackProgress(force: true, overridePosition: clampedSeconds)
    }
  }

  func finishSeeking(
    to seconds: Double,
    persistImmediately: Bool = true
  ) {
    let resumePlayback = seekShouldResumePlayback ?? false
    seekShouldResumePlayback = nil
    let clampedSeconds = prepareSeek(to: seconds)
    let seekGeneration = beginEngineCommand()
    engine.seek(to: clampedSeconds) { [weak self, playbackStateGate] in
      Task { @MainActor in
        guard
          let self,
          resumePlayback,
          playbackStateGate.isCurrentGeneration(seekGeneration)
        else {
          return
        }

        self.play()
      }
    }

    if persistImmediately {
      persistCurrentPlaybackProgress(force: true, overridePosition: clampedSeconds)
    }
  }

  func flushProgress() {
    persistCurrentPlaybackProgress(force: true)
  }

  private func isSupported(url: URL) -> Bool {
    supportedFileExtensions.contains(url.pathExtension.lowercased())
  }

  private func restoreMostRecentPlaybackSessionIfAvailable() {
    guard let entry = library.recentEntries.first else {
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
    subtitles.updateText(for: playbackState.currentTime)
  }

  private func apply(_ actions: [ResumeCoordinator.Action]) {
    for action in actions {
      performEngineCommand {
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
  }

  private func handlePlaybackDidFinish() {
    playbackRequested = false
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
    performEngineCommand {
      engine.skip(by: interval)
    }
    persistCurrentPlaybackProgress(force: true, overridePosition: projectedPosition)
  }

  private func prepareSeek(to seconds: Double) -> TimeInterval {
    let clampedSeconds = MediaTime(seconds: seconds).clamped(to: playbackState.duration).seconds
    resumeCoordinator.userDidSeek(to: clampedSeconds)
    playbackState.currentTime = clampedSeconds
    subtitles.updateText(for: clampedSeconds)
    return clampedSeconds
  }

  @discardableResult
  private func beginEngineCommand() -> UInt64 {
    playbackStateGate.beginCommand()
    return playbackStateGate.currentGeneration()
  }

  private func performEngineCommand(_ command: () -> Void) {
    beginEngineCommand()
    command()
  }

  private func persistCurrentPlaybackProgress(force: Bool = false, overridePosition: TimeInterval? = nil) {
    guard let currentURL else {
      return
    }

    let duration = max(playbackState.duration, library.entry(for: currentURL)?.duration ?? 0)
    let currentTime = max(overridePosition ?? playbackState.currentTime, 0)

    if duration <= 0 && !force {
      return
    }

    library.upsert(
      for: currentURL,
      position: currentTime,
      duration: duration,
      openedAt: currentOpenedAt,
      selectedSubtitle: subtitles.currentSelection()
    )
  }

  private func clearResumePositionForCurrentFile() {
    guard let currentURL else {
      return
    }

    let duration = max(playbackState.duration, library.entry(for: currentURL)?.duration ?? 0)

    library.upsert(
      for: currentURL,
      position: 0,
      duration: duration,
      openedAt: currentOpenedAt,
      selectedSubtitle: subtitles.currentSelection()
    )
  }
}

private final class PlaybackStateDeliveryGate: @unchecked Sendable {
  struct Token {
    let generation: UInt64
    let sequence: UInt64
  }

  private let lock = NSLock()
  private var generation: UInt64 = 0
  private var nextSequence: UInt64 = 0
  private var lastAcceptedSequence: UInt64 = 0

  func beginCommand() {
    lock.lock()
    defer { lock.unlock() }

    generation &+= 1
    nextSequence = 0
    lastAcceptedSequence = 0
  }

  func makeToken() -> Token {
    lock.lock()
    defer { lock.unlock() }

    nextSequence &+= 1
    return Token(generation: generation, sequence: nextSequence)
  }

  func currentGeneration() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }

    return generation
  }

  func isCurrentGeneration(_ candidate: UInt64) -> Bool {
    lock.lock()
    defer { lock.unlock() }

    return candidate == generation
  }

  func accepts(_ token: Token) -> Bool {
    lock.lock()
    defer { lock.unlock() }

    guard
      token.generation == generation,
      token.sequence > lastAcceptedSequence
    else {
      return false
    }

    lastAcceptedSequence = token.sequence
    return true
  }
}
