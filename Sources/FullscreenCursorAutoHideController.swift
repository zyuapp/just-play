import AppKit
import Foundation

final class FullscreenCursorAutoHideController {
  private let hideDelay: TimeInterval

  private var cursorMonitor: Any?
  private var hideWorkItem: DispatchWorkItem?
  private weak var window: NSWindow?
  private var previousAcceptsMouseMovedEvents: Bool?

  init(hideDelay: TimeInterval = 1.2) {
    self.hideDelay = hideDelay
  }

  deinit {
    stop()
  }

  func start(window: NSWindow?) {
    guard let window else {
      return
    }

    configure(window: window)

    if cursorMonitor == nil {
      cursorMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
      ) { [weak self] event in
        self?.noteActivity()
        return event
      }
    }

    scheduleHide()
  }

  func stop() {
    hideWorkItem?.cancel()
    hideWorkItem = nil

    if let cursorMonitor {
      NSEvent.removeMonitor(cursorMonitor)
      self.cursorMonitor = nil
    }

    NSCursor.setHiddenUntilMouseMoves(false)
    restoreWindowMouseMovedEvents()
  }

  private func configure(window: NSWindow) {
    if self.window !== window {
      restoreWindowMouseMovedEvents()
      self.window = window
      previousAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
    }

    window.acceptsMouseMovedEvents = true
  }

  private func restoreWindowMouseMovedEvents() {
    if
      let window,
      let previousAcceptsMouseMovedEvents
    {
      window.acceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
    }

    window = nil
    previousAcceptsMouseMovedEvents = nil
  }

  private func noteActivity() {
    NSCursor.setHiddenUntilMouseMoves(false)
    scheduleHide()
  }

  private func scheduleHide() {
    hideWorkItem?.cancel()

    let workItem = DispatchWorkItem {
      NSCursor.setHiddenUntilMouseMoves(true)
    }

    hideWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: workItem)
  }
}
