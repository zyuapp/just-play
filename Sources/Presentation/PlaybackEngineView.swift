import AppKit
import SwiftUI

struct PlaybackEngineView: NSViewRepresentable {
  let engine: VideoSurfaceProviding

  func makeNSView(context: Context) -> NSView {
    engine.makeVideoView()
  }

  func updateNSView(_ nsView: NSView, context: Context) {
  }
}
