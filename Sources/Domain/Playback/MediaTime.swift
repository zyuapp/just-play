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

  func ratio(toDuration duration: TimeInterval) -> Double {
    guard seconds.isFinite, duration > 0 else {
      return 0
    }

    return min(max(seconds / duration, 0), 1)
  }

  static func seconds(forRatio ratio: Double, duration: TimeInterval) -> TimeInterval {
    guard ratio.isFinite, duration.isFinite else {
      return 0
    }

    return min(max(ratio, 0), 1) * max(duration, 0)
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
