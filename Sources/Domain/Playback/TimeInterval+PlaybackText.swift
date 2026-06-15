import Foundation

extension TimeInterval {
  var playbackText: String {
    MediaTime(seconds: self).displayText
  }
}
