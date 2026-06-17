import Foundation
@testable import JustPlay

final class InMemoryRecentLibraryRepository: RecentLibraryRepository {
  private var state: RecentLibraryState

  init(_ state: RecentLibraryState = .empty) {
    self.state = state
  }

  func loadState() -> RecentLibraryState {
    RecentLibraryState(
      recentEntries: state.recentEntries.sorted { $0.lastOpenedAt > $1.lastOpenedAt },
      archivedEntries: state.archivedEntries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    )
  }

  func saveState(_ state: RecentLibraryState) {
    self.state = state
  }
}
