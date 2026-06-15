import Foundation

@MainActor
final class SubtitleService: ObservableObject {
  @Published private(set) var subtitleText: String?
  @Published private(set) var activeFileName: String?
  @Published private(set) var availableTracks: [SubtitleTrackOption] = []
  @Published private(set) var selectedTrackID: String?
  @Published private(set) var timelineCues: [SubtitleCue] = []
  @Published private(set) var activeCueIndex: Int?

  @Published var isEnabled = true {
    didSet {
      refreshSubtitleText()
    }
  }

  var hasTrack: Bool {
    selectedTrackID != nil
  }

  var onSelectionChanged: () -> Void = {}
  var announce: (String) -> Void = { _ in }

  private let parser: SubtitleParser
  private let fileManager: FileManager
  private let setNativeRendering: (Bool) -> Void

  private var loadedTracks: [LoadedSubtitleTrack] = []
  private var cues: [SubtitleCue] = []
  private var lastKnownTime: TimeInterval = 0

  init(
    parser: SubtitleParser,
    fileManager: FileManager = .default,
    setNativeRendering: @escaping (Bool) -> Void
  ) {
    self.parser = parser
    self.fileManager = fileManager
    self.setNativeRendering = setNativeRendering
  }

  func resetForNewVideo() {
    loadedTracks = []
    availableTracks = []
    clearActiveTrack()
  }

  func loadAutoDetectedSubtitle(for videoURL: URL) {
    guard let sidecarURL = sidecarSubtitleURL(for: videoURL) else {
      return
    }

    load(from: sidecarURL, source: .autoDetected, shouldAnnounce: false)
  }

  func restore(selection: RecentPlaybackEntry.SubtitleSelection?) {
    guard let selection else {
      return
    }

    let subtitleURL = selection.resolvedURL
    guard fileManager.fileExists(atPath: subtitleURL.path) else {
      return
    }

    load(from: subtitleURL, source: selection.source, shouldAnnounce: false)
  }

  func loadManualSubtitle(from url: URL) {
    load(from: url, source: .manual)
  }

  func selectTrack(_ trackID: String) {
    guard let track = loadedTracks.first(where: { $0.id == trackID }) else {
      return
    }

    activate(track)
  }

  func removeSelectedTrack() {
    guard let selectedTrackID else {
      clearActiveTrack()
      return
    }

    loadedTracks.removeAll { $0.id == selectedTrackID }
    refreshTrackOptions()

    if let nextTrack = loadedTracks.first {
      activate(nextTrack)
    } else {
      clearActiveTrack()
    }

    onSelectionChanged()
  }

  func updateText(for time: TimeInterval) {
    lastKnownTime = time
    refreshSubtitleText()
  }

  func cueStart(at index: Int) -> TimeInterval? {
    guard timelineCues.indices.contains(index) else {
      return nil
    }

    return timelineCues[index].start
  }

  func currentSelection() -> RecentPlaybackEntry.SubtitleSelection? {
    guard
      let selectedTrackID,
      let track = loadedTracks.first(where: { $0.id == selectedTrackID })
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
      source: track.source
    )
  }

  private func load(from subtitleURL: URL, source: SubtitleSource, shouldAnnounce: Bool = true) {
    do {
      let parsedCues = try parser.parse(url: subtitleURL)
      guard !parsedCues.isEmpty else {
        throw SubtitleError.emptyTrack
      }

      let standardizedURL = subtitleURL.standardizedFileURL
      let track = LoadedSubtitleTrack(
        id: trackID(for: standardizedURL, source: source),
        source: source,
        url: standardizedURL,
        displayName: standardizedURL.lastPathComponent,
        cues: parsedCues
      )

      if let index = loadedTracks.firstIndex(where: { $0.id == track.id }) {
        loadedTracks[index] = track
      } else {
        loadedTracks.append(track)
      }

      refreshTrackOptions()
      activate(track)

      guard shouldAnnounce else {
        return
      }

      if source == .manual {
        announce("Loaded subtitle: \(track.displayName)")
      }

    } catch {
      if source == .manual {
        announce("Unable to read subtitle file.")
      }
    }
  }

  private func activate(_ track: LoadedSubtitleTrack) {
    setNativeRendering(false)
    cues = track.cues
    timelineCues = track.cues
    activeFileName = track.displayName
    selectedTrackID = track.id
    isEnabled = true
    refreshSubtitleText()
    onSelectionChanged()
  }

  private func clearActiveTrack() {
    setNativeRendering(true)
    cues = []
    timelineCues = []
    activeCueIndex = nil
    subtitleText = nil
    activeFileName = nil
    selectedTrackID = nil
  }

  private func refreshTrackOptions() {
    availableTracks = loadedTracks.map {
      SubtitleTrackOption(
        id: $0.id,
        displayName: $0.displayName,
        sourceLabel: $0.source.displayName
      )
    }
  }

  private func refreshSubtitleText() {
    activeCueIndex = findActiveCueIndex(at: lastKnownTime)

    guard isEnabled, !cues.isEmpty, let activeCueIndex else {
      subtitleText = nil
      return
    }

    subtitleText = cues[activeCueIndex].text
  }

  private func findActiveCueIndex(at time: TimeInterval) -> Int? {
    guard !cues.isEmpty else {
      return nil
    }

    var lowerBound = 0
    var upperBound = cues.count - 1

    while lowerBound <= upperBound {
      let middleIndex = lowerBound + ((upperBound - lowerBound) / 2)
      let cue = cues[middleIndex]

      if time < cue.start {
        upperBound = middleIndex - 1
      } else if time > cue.end {
        lowerBound = middleIndex + 1
      } else {
        return middleIndex
      }
    }

    return nil
  }

  private func trackID(for url: URL, source: SubtitleSource) -> String {
    "\(source.rawValue)::\(url.path)"
  }

  private func sidecarSubtitleURL(for videoURL: URL) -> URL? {
    let directoryURL = videoURL.deletingLastPathComponent()
    let baseName = videoURL.deletingPathExtension().lastPathComponent.lowercased()

    guard let fileURLs = try? fileManager.contentsOfDirectory(
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
}

private extension SubtitleService {
  struct LoadedSubtitleTrack: Identifiable {
    let id: String
    let source: SubtitleSource
    let url: URL
    let displayName: String
    let cues: [SubtitleCue]
  }

  enum SubtitleError: Error {
    case emptyTrack
  }
}
