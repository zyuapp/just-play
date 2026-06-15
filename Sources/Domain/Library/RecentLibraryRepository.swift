import Foundation

struct RecentLibraryState {
  let recentEntries: [RecentPlaybackEntry]
  let archivedEntries: [RecentPlaybackEntry]

  static let empty = RecentLibraryState(recentEntries: [], archivedEntries: [])
}

protocol RecentLibraryRepository {
  func loadState() -> RecentLibraryState
  func saveState(_ state: RecentLibraryState)
}
