import AppKit
import SwiftUI

@MainActor
final class MiniPlayerController: NSObject, ObservableObject {
  @Published private(set) var isPresented = false

  private var panel: NSPanel?
  private weak var presentingWindow: NSWindow?

  func present(viewModel: PlayerViewModel, sourceWindow: NSWindow?) {
    presentingWindow = sourceWindow

    if let panel {
      isPresented = true
      panel.orderFrontRegardless()
      return
    }

    isPresented = true

    // Flip SwiftUI state first so the inline NSViewRepresentable releases the
    // playback view before the floating panel hosts that same AppKit view.
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
    let windowToRestore = presentingWindow
    close()

    NSApplication.shared.activate(ignoringOtherApps: true)
    windowToRestore?.makeKeyAndOrderFront(nil)
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
    presentingWindow = nil
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

      SubtitleOverlayView(
        text: viewModel.subtitleText,
        isVisible: viewModel.currentURL != nil,
        density: .compact
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

      miniControls
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    .background(Color.black)
  }

  private var miniControls: some View {
    HStack(spacing: 8) {
      PlaybackTransportButtons(
        isPlaying: viewModel.playbackState.isPlaying,
        isEnabled: viewModel.currentURL != nil,
        usesSpaceShortcut: false,
        onPlayPause: viewModel.togglePlayPause,
        onSkipBackward: viewModel.skipBackward,
        onSkipForward: viewModel.skipForward
      )

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
