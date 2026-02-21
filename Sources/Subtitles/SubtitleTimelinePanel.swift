import Foundation
import SwiftUI

struct SubtitleTimelinePanel: View {
  let cues: [SubtitleCue]
  let activeCueIndex: Int?
  let activeSubtitleFileName: String?
  let onSelectCue: (Int) -> Void
  var autoCenterActiveCue = true

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      if cues.isEmpty {
        Text("No subtitle lines available.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 10) {
              ForEach(Array(cues.enumerated()), id: \.offset) { index, cue in
                cueRow(cue: cue, index: index)
                  .id(index)
              }
            }
            .padding(.vertical, 4)
          }
          .onAppear {
            centerActiveCue(using: proxy)
          }
          .onChange(of: activeCueIndex) { _ in
            centerActiveCue(using: proxy)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Subtitles")
        .font(.title3.weight(.semibold))

      if let activeSubtitleFileName {
        Text(activeSubtitleFileName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  private func cueRow(cue: SubtitleCue, index: Int) -> some View {
    let isActive = index == activeCueIndex
    let cardFill: Color = isActive ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.06)
    let cardStroke: Color = isActive ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.07)

    return Button {
      onSelectCue(index)
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        Text(formattedTime(cue.start))
          .font(.system(.caption, design: .monospaced).weight(.semibold))
          .foregroundStyle(isActive ? Color.accentColor : .secondary)

        SubtitleTextRenderer.render(cue.text)
          .font(.subheadline.weight(isActive ? .semibold : .regular))
          .multilineTextAlignment(.leading)
          .lineLimit(nil)
          .foregroundStyle(.primary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(cardFill)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(cardStroke, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private func centerActiveCue(using proxy: ScrollViewProxy) {
    guard autoCenterActiveCue, let activeCueIndex else {
      return
    }

    withAnimation(.easeInOut(duration: 0.22)) {
      proxy.scrollTo(activeCueIndex, anchor: .center)
    }
  }

  private func formattedTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else { return "00:00" }

    let totalSeconds = max(Int(seconds.rounded(.down)), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainderSeconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, remainderSeconds)
    }

    return String(format: "%02d:%02d", minutes, remainderSeconds)
  }
}
