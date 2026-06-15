import Foundation

struct ResumePolicy {
  let nearCompletionThreshold: Double

  init(nearCompletionThreshold: Double = 0.98) {
    self.nearCompletionThreshold = nearCompletionThreshold
  }

  func resumePoint(for entry: RecentPlaybackEntry) -> ResumePoint? {
    guard entry.lastPlaybackPosition > 0 else {
      return nil
    }

    guard entry.duration > 0 else {
      return ResumePoint(seconds: entry.lastPlaybackPosition)
    }

    guard entry.progress < nearCompletionThreshold else {
      return nil
    }

    let cappedPosition = min(entry.lastPlaybackPosition, max(entry.duration - 1, 0))
    guard cappedPosition > 0 else {
      return nil
    }

    return ResumePoint(seconds: cappedPosition)
  }
}

extension RecentPlaybackEntry {
  func resumePoint(using policy: ResumePolicy) -> ResumePoint? {
    policy.resumePoint(for: self)
  }
}
