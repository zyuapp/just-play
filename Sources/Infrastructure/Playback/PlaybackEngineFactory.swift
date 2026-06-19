import Foundation

enum PlaybackEngineFactory {
  static func makeDefaultEngine() -> PlaybackEngine & VideoSurfaceProviding {
    #if canImport(VLCKit)
      VLCPlaybackEngine()
    #else
      AVFoundationPlaybackEngine()
    #endif
  }
}
