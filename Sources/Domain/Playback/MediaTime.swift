import Foundation

struct MediaTime: Equatable {
  let seconds: TimeInterval

  init(seconds: TimeInterval) {
    self.seconds = seconds
  }

  func clampedToNonNegative() -> MediaTime {
    MediaTime(seconds: max(seconds, 0))
  }

  func clamped(to duration: TimeInterval) -> MediaTime {
    guard duration > 0 else {
      return clampedToNonNegative()
    }

    return MediaTime(seconds: min(max(seconds, 0), duration))
  }

  var displayText: String {
    guard seconds.isFinite else {
      return "00:00"
    }

    let totalSeconds = max(Int(seconds.rounded(.down)), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainderSeconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, remainderSeconds)
    }

    return String(format: "%02d:%02d", minutes, remainderSeconds)
  }
}
