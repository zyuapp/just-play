import AppKit
import SwiftUI

struct PlayerSurfaceContainer: View {
  @ObservedObject var viewModel: PlayerViewModel
  @StateObject private var miniPlayerController = MiniPlayerController()

  let sourceWindow: () -> NSWindow?

  var body: some View {
    ZStack {
      if miniPlayerController.isPresented {
        miniPlayerPlaceholder
      } else {
        PlaybackEngineView(engine: viewModel.engine)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.black)

        if viewModel.currentURL == nil {
          emptyStateView
        }
      }

      if viewModel.currentURL != nil {
        miniPlayerButton
          .padding(14)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      }

      SubtitleOverlayView(
        text: viewModel.subtitleText,
        isVisible: viewModel.currentURL != nil && !miniPlayerController.isPresented,
        density: .regular
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    .background(Color.black)
    .onDisappear {
      miniPlayerController.close()
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: 12) {
      Image(systemName: "play.square.stack.fill")
        .resizable()
        .scaledToFit()
        .frame(width: 54, height: 54)
        .foregroundStyle(.white.opacity(0.8))

      Text("JustPlay")
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)

      Text(viewModel.statusMessage)
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.7))
        .multilineTextAlignment(.center)

      Button("Open Video...") {
        viewModel.openPanel()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 24)
    .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var miniPlayerPlaceholder: some View {
    VStack(spacing: 12) {
      Image(systemName: "pip")
        .resizable()
        .scaledToFit()
        .frame(width: 48, height: 48)
        .foregroundStyle(.white.opacity(0.78))

      Text(viewModel.currentURL?.lastPathComponent ?? "Mini Player")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(1)

      Button("Return to Main Window") {
        miniPlayerController.dockToMainWindow()
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
  }

  private var miniPlayerButton: some View {
    Button {
      toggleMiniPlayer()
    } label: {
      Image(systemName: miniPlayerController.isPresented ? "pip.exit" : "pip.enter")
    }
    .buttonStyle(.bordered)
    .help(miniPlayerController.isPresented ? "Return to Main Window" : "Open Mini Player")
  }

  private func toggleMiniPlayer() {
    if miniPlayerController.isPresented {
      miniPlayerController.dockToMainWindow()
    } else {
      miniPlayerController.present(viewModel: viewModel, sourceWindow: sourceWindow())
    }
  }
}
