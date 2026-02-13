import Foundation

enum PlaybackEngineFactory {
  static func makeDefaultEngine() -> PlaybackEngine {
    #if canImport(VLCKit)
      VLCPlaybackEngine()
    #else
      AVFoundationPlaybackEngine()
    #endif
  }
}
