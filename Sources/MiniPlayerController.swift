import AppKit
import SwiftUI

@MainActor
final class MiniPlayerController: NSObject, ObservableObject {
  @Published private(set) var isPresented = false

  private var panel: NSPanel?

  func present(viewModel: PlayerViewModel) {
    if let panel {
      isPresented = true
      panel.orderFrontRegardless()
      return
    }

    isPresented = true

    Task { @MainActor [weak self, weak viewModel] in
      guard
        let self,
        let viewModel,
        self.isPresented,
        self.panel == nil
      else {
        return
      }

      self.makePanel(viewModel: viewModel)
    }
  }

  func close() {
    guard let panel else {
      isPresented = false
      return
    }

    panel.close()
  }

  func dockToMainWindow() {
    let closingPanel = panel
    close()

    let mainWindow = NSApplication.shared.windows.first { window in
      if let closingPanel, window === closingPanel {
        return false
      }

      return window.canBecomeMain
    }

    NSApplication.shared.activate(ignoringOtherApps: true)
    mainWindow?.makeKeyAndOrderFront(nil)
  }

  private func makePanel(viewModel: PlayerViewModel) {
    guard panel == nil else {
      return
    }

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.title = "JustPlay Mini Player"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.minSize = NSSize(width: 320, height: 180)
    panel.delegate = self

    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true

    panel.contentViewController = NSHostingController(
      rootView: MiniPlayerPanelContent(
        viewModel: viewModel,
        onDock: { [weak self] in
          self?.dockToMainWindow()
        }
      )
    )

    if let screenFrame = NSScreen.main?.visibleFrame {
      let origin = NSPoint(
        x: screenFrame.maxX - panel.frame.width - 28,
        y: screenFrame.maxY - panel.frame.height - 28
      )
      panel.setFrameOrigin(origin)
    }

    self.panel = panel
    panel.orderFrontRegardless()
  }
}

extension MiniPlayerController: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    panel?.contentViewController = nil
    panel = nil
    isPresented = false
  }
}

private struct MiniPlayerPanelContent: View {
  @ObservedObject var viewModel: PlayerViewModel

  let onDock: () -> Void

  var body: some View {
    ZStack {
      PlaybackEngineView(engine: viewModel.engine)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)

      subtitleOverlay

      miniControls
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    .background(Color.black)
  }

  @ViewBuilder
  private var subtitleOverlay: some View {
    if
      let subtitleText = viewModel.subtitleText,
      !subtitleText.isEmpty,
      viewModel.currentURL != nil
    {
      SubtitleTextRenderer.render(subtitleText)
        .font(.system(size: 18, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 54)
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
    }
  }

  private var miniControls: some View {
    HStack(spacing: 8) {
      Button(action: viewModel.togglePlayPause) {
        Image(systemName: viewModel.playbackState.isPlaying ? "pause.fill" : "play.fill")
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.currentURL == nil)

      Button(action: viewModel.skipBackward) {
        Image(systemName: "gobackward.10")
      }
      .disabled(viewModel.currentURL == nil)

      Button(action: viewModel.skipForward) {
        Image(systemName: "goforward.10")
      }
      .disabled(viewModel.currentURL == nil)

      Spacer(minLength: 8)

      Button(action: onDock) {
        Image(systemName: "pip.exit")
      }
      .buttonStyle(.bordered)
      .help("Return to Main Window")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    }
  }
}
