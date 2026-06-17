import XCTest
@testable import JustPlay

final class FullscreenSubtitlePanelVisibilityTests: XCTestCase {
  func testHotspotHoverShowsPanel() {
    var state = FullscreenSubtitlePanelVisibility()

    let effect = state.hotspotHoverChanged(true)

    XCTAssertEqual(effect, .show)
    XCTAssertTrue(state.isVisible)
  }

  func testPanelHoverShowsPanel() {
    var state = FullscreenSubtitlePanelVisibility()

    let effect = state.panelHoverChanged(true)

    XCTAssertEqual(effect, .show)
    XCTAssertTrue(state.isVisible)
  }

  func testLeavingHotspotSchedulesHideThenHides() {
    var state = FullscreenSubtitlePanelVisibility()
    _ = state.hotspotHoverChanged(true)

    let effect = state.hotspotHoverChanged(false)
    XCTAssertEqual(effect, .scheduleHide)
    XCTAssertTrue(state.isVisible)

    state.hideIfIdle()
    XCTAssertFalse(state.isVisible)
  }

  func testHideIsSuppressedWhilePanelStillHovered() {
    var state = FullscreenSubtitlePanelVisibility()
    _ = state.hotspotHoverChanged(true)
    _ = state.panelHoverChanged(true)
    _ = state.hotspotHoverChanged(false)

    state.hideIfIdle()
    XCTAssertTrue(state.isVisible)

    _ = state.panelHoverChanged(false)
    state.hideIfIdle()
    XCTAssertFalse(state.isVisible)
  }

  func testResetClearsVisibilityAndHover() {
    var state = FullscreenSubtitlePanelVisibility()
    _ = state.hotspotHoverChanged(true)
    _ = state.panelHoverChanged(true)

    state.reset()
    XCTAssertFalse(state.isVisible)

    state.hideIfIdle()
    XCTAssertFalse(state.isVisible)
  }
}
