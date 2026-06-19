import AppKit

protocol VideoSurfaceProviding: AnyObject {
  func makeVideoView() -> NSView
}
