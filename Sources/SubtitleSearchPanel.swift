import SwiftUI

struct SubtitleSearchPanel: View {
  @Binding var apiKey: String
  @Binding var query: String
  @Binding var languageCode: String
  let languageOptions: [SubtitleLanguageOption]
  let isConfigured: Bool
  let hasSubtitleTrack: Bool
  let subtitlesEnabled: Bool
  let isLoading: Bool
  let statusMessage: String?
  let results: [RemoteSubtitleSearchResult]
  let activeDownloadID: Int?
  let availableTracks: [SubtitleTrackOption]
  let selectedTrackID: String?
  let onSaveAPIKey: () -> Void
  let onAddSubtitle: () -> Void
  let onSelectTrack: (String) -> Void
  let onToggleSubtitles: () -> Void
  let onRemoveSubtitle: () -> Void
  let onUseCurrentFileName: () -> Void
  let onSearch: () -> Void
  let onDownload: (RemoteSubtitleSearchResult) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(spacing: 10) {
          Text("Subtitles")
            .font(.title2.weight(.semibold))

          Spacer()

          if isLoading {
            ProgressView()
              .controlSize(.small)
          }
        }

        sectionCard(title: "OpenSubtitles") {
          VStack(alignment: .leading, spacing: 12) {
            Text("API Key")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)

            HStack(spacing: 10) {
              TextField("Enter API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

              Button("Save") {
                onSaveAPIKey()
              }
              .buttonStyle(.borderedProminent)
            }
          }
        }

        sectionCard(title: "Subtitle Library") {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
              Button("Import Subtitle...") {
                onAddSubtitle()
              }

              if hasSubtitleTrack {
                Button(subtitlesEnabled ? "Hide" : "Show") {
                  onToggleSubtitles()
                }

                Button("Remove Selected") {
                  onRemoveSubtitle()
                }
              }
            }

            if availableTracks.isEmpty {
              Text("No subtitle tracks loaded yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
              VStack(alignment: .leading, spacing: 8) {
                Text("Choose active subtitle")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)

                ForEach(availableTracks) { track in
                  subtitleTrackRow(track)
                }
              }
            }
          }
        }

        sectionCard(title: "Search Online") {
          VStack(alignment: .leading, spacing: 12) {
            TextField("Search by video title", text: $query)
              .textFieldStyle(.roundedBorder)
              .disabled(!isConfigured || isLoading)

            HStack(spacing: 12) {
              Picker("Language", selection: $languageCode) {
                ForEach(languageOptions) { option in
                  Text(option.title).tag(option.code)
                }
              }
              .pickerStyle(.menu)
              .frame(width: 220)
              .disabled(!isConfigured || isLoading)

              Spacer(minLength: 8)

              Button("Use File Name") {
                onUseCurrentFileName()
              }
              .disabled(!isConfigured || isLoading)

              Button("Search") {
                onSearch()
              }
              .buttonStyle(.borderedProminent)
              .disabled(!isConfigured || isLoading)
            }
          }
        }

        sectionCard(title: "Results") {
          VStack(alignment: .leading, spacing: 10) {
            if let statusMessage, !statusMessage.isEmpty {
              Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if results.isEmpty {
              Text("No subtitle results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            } else {
              ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                  ForEach(results) { result in
                    subtitleRow(for: result)
                  }
                }
                .padding(.vertical, 2)
              }
              .frame(maxHeight: 280)
            }
          }
        }
      }
      .padding(24)
    }
    .frame(minWidth: 780, minHeight: 540)
  }

  private func sectionCard<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)

      content()
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(0.06))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.white.opacity(0.1), lineWidth: 1)
    }
  }

  private func subtitleTrackRow(_ track: SubtitleTrackOption) -> some View {
    let isSelected = selectedTrackID == track.id

    return Button {
      onSelectTrack(track.id)
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(track.displayName)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)

          Text(track.sourceLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 8)

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? .blue : .secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.04))
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(isSelected ? Color.blue.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private func subtitleRow(for result: RemoteSubtitleSearchResult) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(result.title ?? result.fileName)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)

        Text(result.fileName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text(result.languageName ?? result.languageCode.uppercased())
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        if let release = result.release, !release.isEmpty {
          Text(release)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 12)

      Button(activeDownloadID == result.id ? "Downloading..." : "Download") {
        onDownload(result)
      }
      .buttonStyle(.bordered)
      .disabled(activeDownloadID != nil)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.white.opacity(0.06))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
    }
  }
}
