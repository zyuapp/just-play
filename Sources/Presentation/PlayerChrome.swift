import SwiftUI

enum SubtitleOverlayDensity {
  case regular
  case compact

  var metrics: SubtitleOverlayMetrics {
    switch self {
    case .regular:
      return SubtitleOverlayMetrics(
        fontSize: 24,
        horizontalPadding: 16,
        verticalPadding: 10,
        outerHorizontalPadding: 28,
        bottomPadding: 26
      )
    case .compact:
      return SubtitleOverlayMetrics(
        fontSize: 18,
        horizontalPadding: 12,
        verticalPadding: 7,
        outerHorizontalPadding: 18,
        bottomPadding: 54
      )
    }
  }
}

struct SubtitleOverlayMetrics {
  let fontSize: CGFloat
  let horizontalPadding: CGFloat
  let verticalPadding: CGFloat
  let outerHorizontalPadding: CGFloat
  let bottomPadding: CGFloat
}

struct SubtitleOverlayView: View {
  let text: String?
  let isVisible: Bool
  let density: SubtitleOverlayDensity

  var body: some View {
    let metrics = density.metrics

    if
      isVisible,
      let text,
      !text.isEmpty
    {
      SubtitleTextRenderer.render(text)
        .font(.system(size: metrics.fontSize, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, metrics.outerHorizontalPadding)
        .padding(.bottom, metrics.bottomPadding)
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
    }
  }
}

struct PlaybackTransportButtons: View {
  let isPlaying: Bool
  let isEnabled: Bool
  let usesSpaceShortcut: Bool
  let onPlayPause: () -> Void
  let onSkipBackward: () -> Void
  let onSkipForward: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      playPauseButton

      Button(action: onSkipBackward) {
        Image(systemName: "gobackward.10")
      }
      .disabled(!isEnabled)

      Button(action: onSkipForward) {
        Image(systemName: "goforward.10")
      }
      .disabled(!isEnabled)
    }
  }

  @ViewBuilder
  private var playPauseButton: some View {
    if usesSpaceShortcut {
      basePlayPauseButton
        .keyboardShortcut(.space, modifiers: [])
    } else {
      basePlayPauseButton
    }
  }

  private var basePlayPauseButton: some View {
    Button(action: onPlayPause) {
      Image(systemName: isPlaying ? "pause.fill" : "play.fill")
    }
    .buttonStyle(.borderedProminent)
    .disabled(!isEnabled)
  }
}
