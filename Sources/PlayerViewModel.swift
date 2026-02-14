import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PlayerViewModel: ObservableObject {
  @Published private(set) var playbackState: PlaybackState = .initial
  @Published private(set) var currentURL: URL?
  @Published private(set) var statusMessage = "Drop an MP4 or MKV file, or open one from the menu."
  @Published private(set) var recentEntries: [RecentPlaybackEntry]
  @Published private(set) var subtitleText: String?
  @Published private(set) var activeSubtitleFileName: String?
  @Published private(set) var availableSubtitleTracks: [SubtitleTrackOption] = []
  @Published private(set) var selectedSubtitleTrackID: String?
  @Published var openSubtitlesAPIKey: String
  @Published var subtitleSearchQuery = ""
  @Published var subtitleSearchLanguageCode = SubtitleLanguageOption.anyCode
  @Published private(set) var subtitleSearchResults: [RemoteSubtitleSearchResult] = []
  @Published private(set) var subtitleSearchMessage: String?
  @Published private(set) var subtitleSearchIsLoading = false
  @Published private(set) var subtitleDownloadInFlightID: Int?

  @Published var subtitlesEnabled = true {
    didSet {
      updateSubtitleText(for: playbackState.currentTime)
    }
  }

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

  var hasSubtitleTrack: Bool {
    selectedSubtitleTrackID != nil
  }

  var isSubtitleAPIConfigured: Bool {
    !openSubtitlesAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private let recentPlaybackStore: RecentPlaybackStore
  private var subtitleClient: OpenSubtitlesClient
  private let supportedFileExtensions = Set(["mp4", "m4v", "mkv"])
  private let maxRecentEntries = 50
  private let openSubtitlesAPIKeyDefaultsKey = "OpenSubtitlesAPIKey"
  private let subtitleSearchLanguageDefaultsKey = "SubtitleSearchLanguageCode"
  private let downloadedSubtitleDirectoryName = "downloaded-subtitles"

  private var loadedSubtitleTracks: [LoadedSubtitleTrack] = []
  private var subtitleCues: [SubtitleCue] = []
  private var pendingResumeSeek: TimeInterval?
  private var currentOpenedAt = Date()

  private var playbackProgressTimer: Timer?
  private var appWillTerminateObserver: NSObjectProtocol?

  init(
    engine: PlaybackEngine = PlaybackEngineFactory.makeDefaultEngine(),
    recentPlaybackStore: RecentPlaybackStore = RecentPlaybackStore()
  ) {
    self.engine = engine
    self.recentPlaybackStore = recentPlaybackStore

    let storedKey = UserDefaults.standard.string(forKey: openSubtitlesAPIKeyDefaultsKey)
      ?? ProcessInfo.processInfo.environment["OPEN_SUBTITLES_API_KEY"]
      ?? ""
    let storedSubtitleLanguage = UserDefaults.standard.string(forKey: subtitleSearchLanguageDefaultsKey)
      ?? SubtitleLanguageOption.anyCode

    openSubtitlesAPIKey = storedKey
    subtitleSearchLanguageCode = SubtitleLanguageOption.supportedCodes.contains(storedSubtitleLanguage)
      ? storedSubtitleLanguage
      : SubtitleLanguageOption.anyCode
    subtitleClient = PlayerViewModel.makeSubtitleClient(apiKey: storedKey)

    recentEntries = recentPlaybackStore.loadEntries()
    if !isSubtitleAPIConfigured {
      subtitleSearchMessage = "Add your OpenSubtitles API key to enable online subtitle search."
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

    startPlaybackProgressTimer()
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
    subtitleSearchQuery = normalizedSubtitleQuery(from: normalizedURL)
    subtitleSearchResults = []
    if isSubtitleAPIConfigured {
      subtitleSearchMessage = "Search online subtitles for this video."
    }

    let resumePosition = resumePosition(for: normalizedURL)
    pendingResumeSeek = resumePosition

    if resumePosition != nil {
      statusMessage = "\(normalizedURL.lastPathComponent) (resuming)"
    } else {
      statusMessage = normalizedURL.lastPathComponent
    }

    resetSubtitleStateForCurrentVideo()
    loadAutoDetectedSubtitle(for: normalizedURL)
    restorePersistedSubtitleSelection(for: normalizedURL)

    engine.load(url: normalizedURL, autoplay: autoplay)
    NSDocumentController.shared.noteNewRecentDocumentURL(normalizedURL)

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

  func selectSubtitleTrack(_ trackID: String) {
    guard let track = loadedSubtitleTracks.first(where: { $0.id == trackID }) else {
      return
    }

    activateSubtitleTrack(track)
  }

  var subtitleLanguageOptions: [SubtitleLanguageOption] {
    SubtitleLanguageOption.all
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

    loadSubtitle(from: subtitleURL, source: .manual)
  }

  func removeSubtitleTrack() {
    guard let selectedSubtitleTrackID else {
      clearActiveSubtitleTrack()
      return
    }

    loadedSubtitleTracks.removeAll { $0.id == selectedSubtitleTrackID }
    refreshSubtitleTrackOptions()

    if let nextTrack = loadedSubtitleTracks.first {
      activateSubtitleTrack(nextTrack)
    } else {
      clearActiveSubtitleTrack()
    }

    persistCurrentPlaybackProgress(force: true)
  }

  func saveOpenSubtitlesAPIKey() {
    let trimmed = openSubtitlesAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    openSubtitlesAPIKey = trimmed

    if trimmed.isEmpty {
      UserDefaults.standard.removeObject(forKey: openSubtitlesAPIKeyDefaultsKey)
      subtitleSearchResults = []
      subtitleSearchMessage = "Add your OpenSubtitles API key to enable online subtitle search."
    } else {
      UserDefaults.standard.set(trimmed, forKey: openSubtitlesAPIKeyDefaultsKey)
      subtitleSearchMessage = "API key saved."
    }

    subtitleClient = PlayerViewModel.makeSubtitleClient(apiKey: trimmed)
  }

  func useCurrentFileNameForSubtitleSearch() {
    guard let currentURL else {
      return
    }

    subtitleSearchQuery = normalizedSubtitleQuery(from: currentURL)
  }

  func searchSubtitles() {
    subtitleClient = PlayerViewModel.makeSubtitleClient(apiKey: openSubtitlesAPIKey)
    UserDefaults.standard.set(subtitleSearchLanguageCode, forKey: subtitleSearchLanguageDefaultsKey)

    guard isSubtitleAPIConfigured else {
      subtitleSearchMessage = "Add your OpenSubtitles API key to search subtitles online."
      return
    }

    let query = subtitleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      subtitleSearchMessage = "Enter a title or use the current file name."
      subtitleSearchResults = []
      return
    }

    subtitleSearchIsLoading = true
    subtitleSearchMessage = "Searching subtitles..."
    subtitleSearchResults = []

    Task {
      do {
        let language = subtitleSearchLanguageCode == SubtitleLanguageOption.anyCode
          ? nil
          : subtitleSearchLanguageCode
        let results = try await subtitleClient.searchSubtitles(query: query, language: language)
        subtitleSearchResults = results
        subtitleSearchIsLoading = false
        subtitleSearchMessage = results.isEmpty ? "No subtitles found." : "Found \(results.count) subtitles."
      } catch {
        subtitleSearchIsLoading = false
        subtitleSearchMessage = error.localizedDescription
      }
    }
  }

  func downloadSubtitle(_ result: RemoteSubtitleSearchResult) {
    guard subtitleDownloadInFlightID == nil else {
      return
    }

    guard let currentURL else {
      subtitleSearchMessage = "Open a video before downloading subtitles."
      return
    }

    subtitleDownloadInFlightID = result.id
    subtitleSearchMessage = "Downloading \(result.fileName)..."

    Task {
      do {
        let downloaded = try await subtitleClient.downloadSubtitle(fileID: result.fileID)
        let savedURL = try saveDownloadedSubtitle(
          text: downloaded.subtitleText,
          fileName: downloaded.fileName,
          for: currentURL
        )
        loadSubtitle(from: savedURL, source: .remoteDownloaded)
        subtitleDownloadInFlightID = nil
      } catch {
        subtitleDownloadInFlightID = nil
        subtitleSearchMessage = error.localizedDescription
      }
    }
  }

  func togglePlayPause() {
    if playbackState.isPlaying {
      engine.pause()
    } else {
      engine.play()
    }
  }

  func skipForward() {
    engine.skip(by: 10)
  }

  func skipBackward() {
    engine.skip(by: -10)
  }

  func seek(to seconds: Double) {
    engine.seek(to: seconds)
  }

  private func isSupported(url: URL) -> Bool {
    supportedFileExtensions.contains(url.pathExtension.lowercased())
  }

  private func handlePlaybackStateChange(_ state: PlaybackState) {
    playbackState = state
    applyPendingResumeSeekIfNeeded(with: state)
    updateSubtitleText(for: state.currentTime)
  }

  private func handlePlaybackDidFinish() {
    clearResumePositionForCurrentFile()
  }

  private func applyPendingResumeSeekIfNeeded(with state: PlaybackState) {
    guard
      let pendingResumeSeek,
      state.duration > 0
    else {
      return
    }

    let clampedSeek = min(max(pendingResumeSeek, 0), max(state.duration - 1, 0))
    self.pendingResumeSeek = nil

    guard clampedSeek > 0 else {
      return
    }

    engine.seek(to: clampedSeek)
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

  private func persistCurrentPlaybackProgress(force: Bool = false) {
    guard let currentURL else {
      return
    }

    let duration = max(playbackState.duration, existingEntry(for: currentURL)?.duration ?? 0)
    let currentTime = max(playbackState.currentTime, 0)

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

    let selectedSubtitle = currentSubtitleSelection()

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

    recentPlaybackStore.saveEntries(recentEntries)
  }

  private func existingEntry(for url: URL) -> RecentPlaybackEntry? {
    let normalizedPath = RecentPlaybackEntry.normalizedPath(for: url)
    return recentEntries.first { $0.filePath == normalizedPath }
  }

  private func resumePosition(for url: URL) -> TimeInterval? {
    guard let entry = existingEntry(for: url) else {
      return nil
    }

    guard entry.duration > 0 else {
      return nil
    }

    let progress = entry.lastPlaybackPosition / entry.duration
    if progress >= 0.98 {
      return nil
    }

    guard entry.lastPlaybackPosition > 0 else {
      return nil
    }

    return entry.lastPlaybackPosition
  }

  private func resetSubtitleStateForCurrentVideo() {
    loadedSubtitleTracks = []
    availableSubtitleTracks = []
    clearActiveSubtitleTrack()
  }

  private func restorePersistedSubtitleSelection(for videoURL: URL) {
    guard let selection = existingEntry(for: videoURL)?.selectedSubtitle else {
      return
    }

    let subtitleURL = selection.resolvedURL
    guard FileManager.default.fileExists(atPath: subtitleURL.path) else {
      return
    }

    loadSubtitle(from: subtitleURL, source: subtitleSource(from: selection.source), shouldAnnounce: false)
  }

  private func loadAutoDetectedSubtitle(for videoURL: URL) {
    guard let sidecarURL = sidecarSubtitleURL(for: videoURL) else {
      return
    }

    loadSubtitle(from: sidecarURL, source: .autoDetected, shouldAnnounce: false)
  }

  private func loadSubtitle(from subtitleURL: URL, source: SubtitleSource, shouldAnnounce: Bool = true) {
    do {
      let parsedCues = try SRTParser.parse(url: subtitleURL)
      guard !parsedCues.isEmpty else {
        throw SubtitleError.emptyTrack
      }

      let standardizedURL = subtitleURL.standardizedFileURL
      let track = LoadedSubtitleTrack(
        id: subtitleTrackID(for: standardizedURL, source: source),
        source: source,
        url: standardizedURL,
        displayName: standardizedURL.lastPathComponent,
        cues: parsedCues
      )

      if let index = loadedSubtitleTracks.firstIndex(where: { $0.id == track.id }) {
        loadedSubtitleTracks[index] = track
      } else {
        loadedSubtitleTracks.append(track)
      }

      refreshSubtitleTrackOptions()
      activateSubtitleTrack(track)

      guard shouldAnnounce else {
        return
      }

      if source == .manual {
        statusMessage = "Loaded subtitle: \(track.displayName)"
      }

      if source == .remoteDownloaded {
        subtitleSearchMessage = "Loaded subtitle: \(track.displayName)"
      }
    } catch {
      if source == .manual || source == .remoteDownloaded {
        statusMessage = "Unable to read subtitle file."
      }
    }
  }

  private func activateSubtitleTrack(_ track: LoadedSubtitleTrack) {
    subtitleCues = track.cues
    activeSubtitleFileName = track.displayName
    selectedSubtitleTrackID = track.id
    subtitlesEnabled = true
    updateSubtitleText(for: playbackState.currentTime)
    persistCurrentPlaybackProgress(force: true)
  }

  private func clearActiveSubtitleTrack() {
    subtitleCues = []
    subtitleText = nil
    activeSubtitleFileName = nil
    selectedSubtitleTrackID = nil
  }

  private func refreshSubtitleTrackOptions() {
    availableSubtitleTracks = loadedSubtitleTracks.map {
      SubtitleTrackOption(
        id: $0.id,
        displayName: $0.displayName,
        sourceLabel: $0.source.displayName
      )
    }
  }

  private func saveDownloadedSubtitle(text: String, fileName: String, for videoURL: URL) throws -> URL {
    let baseDirectory = try downloadedSubtitlesDirectoryURL(for: videoURL)
    let safeName = sanitizedSubtitleFileName(fileName)
    let outputURL = baseDirectory.appendingPathComponent("\(UUID().uuidString)-\(safeName)", isDirectory: false)

    guard let data = text.data(using: .utf8) else {
      throw SubtitleError.unreadableTrack
    }

    try data.write(to: outputURL, options: .atomic)
    return outputURL
  }

  private func downloadedSubtitlesDirectoryURL(for videoURL: URL) throws -> URL {
    let bundleID = Bundle.main.bundleIdentifier ?? "com.justplay.native"
    let appSupportDirectory = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )

    let videoKey = Data(videoURL.path.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
    let directoryURL = appSupportDirectory
      .appendingPathComponent(bundleID, isDirectory: true)
      .appendingPathComponent(downloadedSubtitleDirectoryName, isDirectory: true)
      .appendingPathComponent(videoKey, isDirectory: true)

    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
  }

  private func sanitizedSubtitleFileName(_ fileName: String) -> String {
    let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = "subtitle.srt"
    guard !trimmed.isEmpty else {
      return fallback
    }

    let forbidden = CharacterSet(charactersIn: "/:\\")
    let sanitized = trimmed.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }
    let normalized = sanitized.joined()
    return normalized.isEmpty ? fallback : normalized
  }

  private func currentSubtitleSelection() -> RecentPlaybackEntry.SubtitleSelection? {
    guard
      let selectedSubtitleTrackID,
      let track = loadedSubtitleTracks.first(where: { $0.id == selectedSubtitleTrackID })
    else {
      return nil
    }

    let bookmarkData = try? track.url.bookmarkData(
      options: .minimalBookmark,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    return RecentPlaybackEntry.SubtitleSelection(
      filePath: track.url.path,
      bookmarkData: bookmarkData,
      displayName: track.displayName,
      source: persistedSubtitleSource(from: track.source)
    )
  }

  private func subtitleSource(from source: RecentPlaybackEntry.SubtitleSelection.Source) -> SubtitleSource {
    switch source {
    case .autoDetected:
      return .autoDetected
    case .manual:
      return .manual
    case .remoteDownloaded:
      return .remoteDownloaded
    }
  }

  private func persistedSubtitleSource(from source: SubtitleSource) -> RecentPlaybackEntry.SubtitleSelection.Source {
    switch source {
    case .autoDetected:
      return .autoDetected
    case .manual:
      return .manual
    case .remoteDownloaded:
      return .remoteDownloaded
    }
  }

  private func subtitleTrackID(for url: URL, source: SubtitleSource) -> String {
    "\(source.rawValue)::\(url.path)"
  }

  private func sidecarSubtitleURL(for videoURL: URL) -> URL? {
    let directoryURL = videoURL.deletingLastPathComponent()
    let baseName = videoURL.deletingPathExtension().lastPathComponent.lowercased()

    guard let fileURLs = try? FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return nil
    }

    return fileURLs.first {
      $0.pathExtension.lowercased() == "srt"
        && $0.deletingPathExtension().lastPathComponent.lowercased() == baseName
    }
  }

  private func updateSubtitleText(for time: TimeInterval) {
    guard subtitlesEnabled else {
      subtitleText = nil
      return
    }

    guard !subtitleCues.isEmpty else {
      subtitleText = nil
      return
    }

    subtitleText = subtitleCues.first { $0.contains(time) }?.text
  }

  private func subtitleContentTypes() -> [UTType] {
    if let srtType = UTType(filenameExtension: "srt") {
      return [srtType, .plainText]
    }

    return [.plainText]
  }

  private func normalizedSubtitleQuery(from videoURL: URL) -> String {
    let rawName = videoURL.deletingPathExtension().lastPathComponent
    return rawName
      .replacingOccurrences(of: ".", with: " ")
      .replacingOccurrences(of: "_", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private extension PlayerViewModel {
  static func makeSubtitleClient(apiKey: String) -> OpenSubtitlesClient {
    let config = OpenSubtitlesClient.Configuration.fromAPIKey(apiKey)
    return OpenSubtitlesClient(configuration: config)
  }
}

private extension PlayerViewModel {
  struct LoadedSubtitleTrack: Identifiable {
    let id: String
    let source: SubtitleSource
    let url: URL
    let displayName: String
    let cues: [SubtitleCue]
  }

  enum SubtitleSource: String {
    case autoDetected
    case manual
    case remoteDownloaded

    var displayName: String {
      switch self {
      case .autoDetected:
        return "Auto"
      case .manual:
        return "Imported"
      case .remoteDownloaded:
        return "Downloaded"
      }
    }
  }

  enum SubtitleError: Error {
    case emptyTrack
    case unreadableTrack
  }
}
