import XCTest
@testable import JustPlay

final class MediaTimeTests: XCTestCase {
  func testDisplayTextUnderOneHour() {
    XCTAssertEqual(MediaTime(seconds: 0).displayText, "00:00")
    XCTAssertEqual(MediaTime(seconds: 65).displayText, "01:05")
    XCTAssertEqual(MediaTime(seconds: 599).displayText, "09:59")
  }

  func testDisplayTextWithHours() {
    XCTAssertEqual(MediaTime(seconds: 3661).displayText, "1:01:01")
    XCTAssertEqual(MediaTime(seconds: 3723.5).displayText, "1:02:03")
  }

  func testDisplayTextRoundsDown() {
    XCTAssertEqual(MediaTime(seconds: 59.9).displayText, "00:59")
  }

  func testDisplayTextForNonFiniteOrNegative() {
    XCTAssertEqual(MediaTime(seconds: -5).displayText, "00:00")
    XCTAssertEqual(MediaTime(seconds: .infinity).displayText, "00:00")
    XCTAssertEqual(MediaTime(seconds: .nan).displayText, "00:00")
  }

  func testClampedToNonNegative() {
    XCTAssertEqual(MediaTime(seconds: -5).clampedToNonNegative(), MediaTime(seconds: 0))
    XCTAssertEqual(MediaTime(seconds: 5).clampedToNonNegative(), MediaTime(seconds: 5))
  }

  func testClampedToDuration() {
    XCTAssertEqual(MediaTime(seconds: 50).clamped(to: 100), MediaTime(seconds: 50))
    XCTAssertEqual(MediaTime(seconds: 150).clamped(to: 100), MediaTime(seconds: 100))
    XCTAssertEqual(MediaTime(seconds: -5).clamped(to: 100), MediaTime(seconds: 0))
  }

  func testClampedWithUnknownDurationFloorsAtZero() {
    XCTAssertEqual(MediaTime(seconds: 50).clamped(to: 0), MediaTime(seconds: 50))
    XCTAssertEqual(MediaTime(seconds: -5).clamped(to: 0), MediaTime(seconds: 0))
  }

  func testPlaybackTextExtensionDelegatesToMediaTime() {
    XCTAssertEqual(TimeInterval(65).playbackText, "01:05")
    XCTAssertEqual(TimeInterval(3661).playbackText, "1:01:01")
  }

  func testRatioToDuration() {
    XCTAssertEqual(MediaTime(seconds: 50).ratio(toDuration: 100), 0.5, accuracy: 0.0001)
    XCTAssertEqual(MediaTime(seconds: 150).ratio(toDuration: 100), 1.0, accuracy: 0.0001)
    XCTAssertEqual(MediaTime(seconds: -10).ratio(toDuration: 100), 0.0, accuracy: 0.0001)
    XCTAssertEqual(MediaTime(seconds: 50).ratio(toDuration: 0), 0.0, accuracy: 0.0001)
  }

  func testSecondsForRatio() {
    XCTAssertEqual(MediaTime.seconds(forRatio: 0.5, duration: 100), 50, accuracy: 0.0001)
    XCTAssertEqual(MediaTime.seconds(forRatio: 1.5, duration: 100), 100, accuracy: 0.0001)
    XCTAssertEqual(MediaTime.seconds(forRatio: -0.5, duration: 100), 0, accuracy: 0.0001)
    XCTAssertEqual(MediaTime.seconds(forRatio: 0.5, duration: -100), 0, accuracy: 0.0001)
  }

  func testRatioForNonFiniteInputsReturnsZero() {
    XCTAssertEqual(MediaTime(seconds: .nan).ratio(toDuration: 100), 0.0, accuracy: 0.0001)
    XCTAssertEqual(MediaTime(seconds: .infinity).ratio(toDuration: 100), 0.0, accuracy: 0.0001)
    XCTAssertEqual(MediaTime(seconds: 50).ratio(toDuration: .nan), 0.0, accuracy: 0.0001)
  }

  func testSecondsForNonFiniteInputsReturnsZero() {
    XCTAssertEqual(MediaTime.seconds(forRatio: .nan, duration: 100), 0, accuracy: 0.0001)
    XCTAssertEqual(MediaTime.seconds(forRatio: 0.5, duration: .nan), 0, accuracy: 0.0001)
    XCTAssertEqual(MediaTime.seconds(forRatio: 0.5, duration: .infinity), 0, accuracy: 0.0001)
  }
}
