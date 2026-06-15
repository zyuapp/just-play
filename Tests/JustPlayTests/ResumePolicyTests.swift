import XCTest
@testable import JustPlay

final class ResumePolicyTests: XCTestCase {
  private let policy = ResumePolicy()

  func testReturnsNilWhenPositionIsZero() {
    XCTAssertNil(policy.resumePoint(for: makeEntry(position: 0, duration: 100)))
  }

  func testReturnsNilWhenPositionIsNegative() {
    XCTAssertNil(policy.resumePoint(for: makeEntry(position: -5, duration: 100)))
  }

  func testReturnsPositionWhenDurationUnknown() {
    XCTAssertEqual(policy.resumePoint(for: makeEntry(position: 42, duration: 0)), ResumePoint(seconds: 42))
  }

  func testReturnsPositionForMidPlayback() {
    XCTAssertEqual(policy.resumePoint(for: makeEntry(position: 50, duration: 100)), ResumePoint(seconds: 50))
  }

  func testReturnsNilAtNearCompletionThreshold() {
    XCTAssertNil(policy.resumePoint(for: makeEntry(position: 98, duration: 100)))
  }

  func testReturnsPositionJustBelowThreshold() {
    XCTAssertEqual(policy.resumePoint(for: makeEntry(position: 97, duration: 100)), ResumePoint(seconds: 97))
  }

  func testReturnsNilWhenPositionExceedsDuration() {
    XCTAssertNil(policy.resumePoint(for: makeEntry(position: 150, duration: 100)))
  }

  func testCapsPositionToOneSecondBeforeEnd() {
    XCTAssertEqual(policy.resumePoint(for: makeEntry(position: 9.5, duration: 10)), ResumePoint(seconds: 9))
  }

  func testReturnsNilWhenCappedPositionWouldBeZero() {
    XCTAssertNil(policy.resumePoint(for: makeEntry(position: 0.5, duration: 1)))
  }

  func testRespectsCustomThreshold() {
    let lenientPolicy = ResumePolicy(nearCompletionThreshold: 0.5)
    XCTAssertNil(lenientPolicy.resumePoint(for: makeEntry(position: 60, duration: 100)))
    XCTAssertEqual(lenientPolicy.resumePoint(for: makeEntry(position: 40, duration: 100)), ResumePoint(seconds: 40))
  }

  func testEntryAccessorDelegatesToPolicy() {
    let entry = makeEntry(position: 50, duration: 100)
    XCTAssertEqual(entry.resumePoint(using: policy), policy.resumePoint(for: entry))
  }

  private func makeEntry(position: TimeInterval, duration: TimeInterval) -> RecentPlaybackEntry {
    RecentPlaybackEntry(
      filePath: "/movies/clip.mp4",
      bookmarkData: nil,
      lastPlaybackPosition: position,
      duration: duration,
      lastOpenedAt: Date(),
      fileSize: nil,
      contentModificationDate: nil,
      selectedSubtitle: nil
    )
  }
}
