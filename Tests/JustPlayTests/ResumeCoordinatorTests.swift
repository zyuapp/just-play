import XCTest
@testable import JustPlay

final class ResumeCoordinatorTests: XCTestCase {
  func testAutoplayResumeSeeksOnceThenConfirms() {
    var coordinator = ResumeCoordinator()
    coordinator.beginResume(toPosition: 120, autoplay: true)

    let first = coordinator.reconcile(with: state(isPlaying: true, currentTime: 0, duration: 300))
    XCTAssertEqual(first.actions, [.seek(120)])
    XCTAssertEqual(first.displayTime, 120)

    let second = coordinator.reconcile(with: state(isPlaying: true, currentTime: 120, duration: 300))
    XCTAssertEqual(second.actions, [])
    XCTAssertEqual(second.displayTime, 120)
  }

  func testNonAutoplayResumePrimesPlaybackThenPauses() {
    var coordinator = ResumeCoordinator()
    coordinator.beginResume(toPosition: 42, autoplay: false)

    let first = coordinator.reconcile(with: state(isPlaying: false, currentTime: 0, duration: 120))
    XCTAssertEqual(first.actions, [.seek(42), .play])
    XCTAssertEqual(first.displayTime, 42)

    let second = coordinator.reconcile(with: state(isPlaying: true, currentTime: 42, duration: 120))
    XCTAssertEqual(second.actions, [.pause])
  }

  func testResumeClampsTargetToOneSecondBeforeEnd() {
    var coordinator = ResumeCoordinator()
    coordinator.beginResume(toPosition: 300, autoplay: true)

    let result = coordinator.reconcile(with: state(isPlaying: true, currentTime: 0, duration: 100))
    XCTAssertEqual(result.actions, [.seek(99)])
  }

  func testResumeWithNonPositiveTargetIsDropped() {
    var coordinator = ResumeCoordinator()
    coordinator.beginResume(toPosition: 0.5, autoplay: true)

    let result = coordinator.reconcile(with: state(isPlaying: true, currentTime: 0, duration: 1))
    XCTAssertEqual(result.actions, [])
  }

  func testNoPendingPassesThroughDisplayTime() {
    var coordinator = ResumeCoordinator()

    let result = coordinator.reconcile(with: state(isPlaying: true, currentTime: 33, duration: 100))
    XCTAssertEqual(result.displayTime, 33)
    XCTAssertEqual(result.actions, [])
  }

  func testPausedSeekHoldsRequestedTimeUntilEngineConfirms() {
    var coordinator = ResumeCoordinator()
    coordinator.userDidSeek(to: 60, isPlaying: false)

    let held = coordinator.reconcile(with: state(isPlaying: false, currentTime: 10, duration: 200))
    XCTAssertEqual(held.displayTime, 60)

    let confirmed = coordinator.reconcile(with: state(isPlaying: false, currentTime: 60.2, duration: 200))
    XCTAssertEqual(confirmed.displayTime, 60.2)

    let after = coordinator.reconcile(with: state(isPlaying: false, currentTime: 20, duration: 200))
    XCTAssertEqual(after.displayTime, 20)
  }

  func testPlayingSeekDoesNotHoldDisplayTime() {
    var coordinator = ResumeCoordinator()
    coordinator.userDidSeek(to: 60, isPlaying: true)

    let result = coordinator.reconcile(with: state(isPlaying: true, currentTime: 12, duration: 200))
    XCTAssertEqual(result.displayTime, 12)
  }

  func testUserSeekCancelsPendingResume() {
    var coordinator = ResumeCoordinator()
    coordinator.beginResume(toPosition: 120, autoplay: true)
    coordinator.userDidSeek(to: 30, isPlaying: true)

    let result = coordinator.reconcile(with: state(isPlaying: true, currentTime: 0, duration: 300))
    XCTAssertEqual(result.actions, [])
  }

  private func state(isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) -> PlaybackState {
    PlaybackState(
      isPlaying: isPlaying,
      currentTime: currentTime,
      duration: duration,
      rate: 1.0,
      volume: 1.0,
      isMuted: false
    )
  }
}
