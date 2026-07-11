import Foundation

struct ResumeCoordinator {
  enum Action: Equatable {
    case seek(TimeInterval)
    case play
    case pause
  }

  struct Resolution: Equatable {
    let displayTime: TimeInterval
    let actions: [Action]
  }

  private let confirmationTolerance: TimeInterval
  private var pendingResumeSeek: TimeInterval?
  private var shouldPrimePlayback = false
  private var shouldPauseAfterResume = false
  private var pendingUserSeekTime: TimeInterval?

  init(confirmationTolerance: TimeInterval = 0.35) {
    self.confirmationTolerance = confirmationTolerance
  }

  mutating func beginResume(toPosition position: TimeInterval?, autoplay: Bool) {
    pendingResumeSeek = position
    shouldPrimePlayback = !autoplay && position != nil
    shouldPauseAfterResume = false
    pendingUserSeekTime = nil
  }

  mutating func userDidSeek(to time: TimeInterval) {
    pendingResumeSeek = nil
    shouldPrimePlayback = false
    shouldPauseAfterResume = false
    pendingUserSeekTime = time
  }

  mutating func reconcile(with state: PlaybackState) -> Resolution {
    var displayTime = state.currentTime

    if let pendingUserSeekTime {
      if abs(state.currentTime - pendingUserSeekTime) <= confirmationTolerance {
        self.pendingUserSeekTime = nil
      } else {
        displayTime = pendingUserSeekTime
      }
    }

    var actions: [Action] = []

    if let pendingResumeSeek {
      let seekTarget: TimeInterval
      if state.duration > 0 {
        seekTarget = min(max(pendingResumeSeek, 0), max(state.duration - 1, 0))
      } else {
        seekTarget = max(pendingResumeSeek, 0)
      }

      if seekTarget <= 0 {
        self.pendingResumeSeek = nil
        shouldPrimePlayback = false
        shouldPauseAfterResume = false
      } else if abs(displayTime - seekTarget) <= confirmationTolerance {
        self.pendingResumeSeek = nil

        if shouldPauseAfterResume {
          shouldPauseAfterResume = false
          actions.append(.pause)
        }
      } else {
        actions.append(.seek(seekTarget))
        displayTime = seekTarget

        if shouldPrimePlayback, !state.isPlaying {
          shouldPrimePlayback = false
          shouldPauseAfterResume = true
          actions.append(.play)
        }
      }
    }

    return Resolution(displayTime: displayTime, actions: actions)
  }
}
