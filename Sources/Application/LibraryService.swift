import Foundation

@MainActor
final class LibraryService: ObservableObject {
  @Published private(set) var recentEntries: [RecentPlaybackEntry]
  @Published private(set) var archivedEntries: [RecentPlaybackEntry]

  private let repository: RecentLibraryRepository
  private let resumePolicy: ResumePolicy
  private let maxRecentEntries: Int

  init(
    repository: RecentLibraryRepository,
    resumePolicy: ResumePolicy = ResumePolicy(),
    maxRecentEntries: Int = 50
  ) {
    self.repository = repository
    self.resumePolicy = resumePolicy
    self.maxRecentEntries = maxRecentEntries

    let storedState = repository.loadState()
    recentEntries = storedState.recentEntries
    archivedEntries = storedState.archivedEntries
  }

  func entry(for url: URL) -> RecentPlaybackEntry? {
    let normalizedPath = RecentPlaybackEntry.normalizedPath(for: url)
    return recentEntries.first { $0.filePath == normalizedPath }
  }

  func resumePosition(for url: URL) -> TimeInterval? {
    entry(for: url)?.resumePoint(using: resumePolicy)?.seconds
  }

  func archive(_ entry: RecentPlaybackEntry) {
    recentEntries.removeAll { $0.filePath == entry.filePath }
    archivedEntries.removeAll { $0.filePath == entry.filePath }
    archivedEntries.append(entry)
    archivedEntries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    saveState()
  }

  func restoreArchived(_ entry: RecentPlaybackEntry) {
    archivedEntries.removeAll { $0.filePath == entry.filePath }
    recentEntries.removeAll { $0.filePath == entry.filePath }
    recentEntries.append(entry)
    recentEntries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
    if recentEntries.count > maxRecentEntries {
      recentEntries = Array(recentEntries.prefix(maxRecentEntries))
    }
    saveState()
  }

  func deleteArchivedPermanently(_ entry: RecentPlaybackEntry) {
    archivedEntries.removeAll { $0.filePath == entry.filePath }
    saveState()
  }

  func upsert(
    for url: URL,
    position: TimeInterval,
    duration: TimeInterval,
    openedAt: Date,
    selectedSubtitle: RecentPlaybackEntry.SubtitleSelection?
  ) {
    let normalizedPath = RecentPlaybackEntry.normalizedPath(for: url)
    let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

    let bookmarkData = BookmarkResolver.makeBookmark(for: url)

    let clampedDuration = max(duration, 0)
    let clampedPosition = MediaTime(seconds: position).clamped(to: clampedDuration).seconds

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
    saveState()
  }

  private func saveState() {
    let state = RecentLibraryState(
      recentEntries: recentEntries,
      archivedEntries: archivedEntries
    )
    repository.saveState(state)
  }
}
