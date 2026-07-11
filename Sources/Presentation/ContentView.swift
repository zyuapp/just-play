import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @StateObject private var viewModel = PlayerViewModel()

  @State private var isDropTargeted = false
  @State private var seekPosition: Double = 0
  @State private var isSeeking = false
  @State private var seekStartedWhilePlaying = false
  @State private var isFullscreen = false
  @State private var isHoveringFullscreenControlsRegion = false
  @State private var fullscreenSubtitlePanel = FullscreenSubtitlePanelVisibility()
  @State private var isVolumePopoverPresented = false
  @State private var fullscreenCursorAutoHideController = FullscreenCursorAutoHideController()
  @State private var keyboardMonitor: Any? = nil
  @State private var isSidebarVisible = true
  @State private var fullscreenSubtitleHideWorkItem: DispatchWorkItem?

  private let fullscreenSubtitleHideDelay: TimeInterval = 0.35
  private let playbackRateOptions: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0]

  var body: some View {
    ZStack {
      backgroundLayer

      HStack(spacing: 0) {
        VStack(spacing: isFullscreen ? 0 : 14) {
          if !isFullscreen {
            headerView
          }

          playerSurface
            .frame(maxHeight: .infinity)

          if !isFullscreen {
            controlsView
          }
        }
        .padding(.horizontal, isFullscreen ? 0 : 16)
        .padding(.vertical, isFullscreen ? 0 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if !isFullscreen && isSidebarVisible {
          Divider()
            .overlay(.white.opacity(0.08))

          RecentFilesPanel(
            entries: viewModel.recentEntries,
            archivedEntries: viewModel.archivedEntries,
            currentFilePath: viewModel.currentFilePath,
            onSelect: viewModel.openRecent,
            onRemove: viewModel.removeRecent,
            onRestoreArchived: viewModel.restoreArchivedRecent,
            onDeleteArchivedPermanently: viewModel.deleteArchivedRecentPermanently,
            subtitleCues: viewModel.subtitleTimelineCues,
            activeSubtitleCueIndex: viewModel.activeSubtitleCueIndex,
            activeSubtitleFileName: viewModel.activeSubtitleFileName,
            onAddSubtitle: viewModel.openSubtitlePanel,
            onSelectSubtitleCue: viewModel.seekToSubtitleCue
          )
          .padding(16)
          .frame(width: 320)
          .frame(maxHeight: .infinity, alignment: .topLeading)
          .background(.regularMaterial)
          .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
    }
    .animation(.easeInOut(duration: 0.22), value: isFullscreen)
    .animation(.easeInOut(duration: 0.22), value: isSidebarVisible)
    .onAppear {
      syncFullscreenState()
      setupKeyboardMonitoring()
      DispatchQueue.main.async {
        syncFullscreenState()
      }
    }
    .onDisappear {
      teardownKeyboardMonitoring()
      fullscreenCursorAutoHideController.stop()
      resetFullscreenSubtitlePanelState()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
      syncFullscreenState(from: notification.object as? NSWindow)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
      syncFullscreenState(from: notification.object as? NSWindow)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
      syncFullscreenState(from: notification.object as? NSWindow)
    }
    .onReceive(NotificationCenter.default.publisher(for: AppOpenBus.didRequestOpenURLs)) { notification in
      let urls = AppOpenBus.urls(from: notification)
      guard let firstURL = urls.first else { return }
      viewModel.open(url: firstURL)
    }
    .onChange(of: viewModel.playbackState.currentTime) { newValue in
      guard !isSeeking else { return }
      seekPosition = max(newValue, 0)
    }
    .onChange(of: isFullscreen) { newValue in
      updateFullscreenDependentState(isFullscreen: newValue)
    }
    .onChange(of: viewModel.subtitleTimelineCues.isEmpty) { isEmpty in
      if isEmpty {
        resetFullscreenSubtitlePanelState()
      }
    }
    .onChange(of: viewModel.playbackState.duration) { newValue in
      guard !isSeeking else { return }
      seekPosition = min(seekPosition, max(newValue, 0))
    }
    .frame(minWidth: 1080, minHeight: 640)
  }

  private var playerSurface: some View {
    PlayerSurfaceContainer(
      viewModel: viewModel,
      sourceWindow: currentWindow
    )
    .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : 18, style: .continuous))
    .overlay {
      if !isFullscreen {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(.white.opacity(0.12), lineWidth: 1)
      }
    }
    .shadow(color: .black.opacity(isFullscreen ? 0 : 0.3), radius: isFullscreen ? 0 : 18, x: 0, y: isFullscreen ? 0 : 10)
    .overlay(alignment: .topLeading) {
      if isDropTargeted {
        dropIndicator
      }
    }
    .overlay(alignment: .trailing) {
      fullscreenSubtitleOverlay
    }
    .overlay(alignment: .bottom) {
      fullscreenControlsOverlay
    }
    .simultaneousGesture(
      TapGesture(count: 2)
        .onEnded {
          toggleFullscreen()
        }
    )
    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    .contextMenu {
      Button("Open...") {
        viewModel.openPanel()
      }

      Divider()

      Button("Add Subtitle...") {
        viewModel.openSubtitlePanel()
      }

      if viewModel.hasSubtitleTrack {
        Button(viewModel.subtitlesEnabled ? "Hide Subtitles" : "Show Subtitles") {
          viewModel.subtitlesEnabled.toggle()
        }

        Button("Remove Subtitle") {
          viewModel.removeSubtitleTrack()
        }
      }
    }
  }

  @ViewBuilder
  private var fullscreenSubtitleOverlay: some View {
    if isFullscreen, !viewModel.subtitleTimelineCues.isEmpty {
      ZStack(alignment: .trailing) {
        Color.clear
          .frame(width: 26)
          .frame(maxHeight: .infinity)
          .contentShape(Rectangle())
          .onHover(perform: updateFullscreenSubtitleHotspotHover)

        if fullscreenSubtitlePanel.isVisible {
          SubtitleTimelinePanel(
            cues: viewModel.subtitleTimelineCues,
            activeCueIndex: viewModel.activeSubtitleCueIndex,
            activeSubtitleFileName: viewModel.activeSubtitleFileName,
            onAddSubtitle: viewModel.openSubtitlePanel,
            onSelectCue: viewModel.seekToSubtitleCue
          )
          .padding(14)
          .frame(width: 360)
          .frame(maxHeight: .infinity, alignment: .topLeading)
          .background(.regularMaterial)
          .transition(.move(edge: .trailing).combined(with: .opacity))
          .onHover(perform: updateFullscreenSubtitlePanelHover)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: fullscreenSubtitlePanel.isVisible)
    }
  }

  @ViewBuilder
  private var fullscreenControlsOverlay: some View {
    if isFullscreen {
      ZStack(alignment: .bottom) {
        Color.clear
          .frame(maxWidth: .infinity)
          .frame(height: 172)

        if isHoveringFullscreenControlsRegion {
          controlsView
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .contentShape(Rectangle())
      .onHover { hovering in
        isHoveringFullscreenControlsRegion = hovering
      }
      .animation(.easeInOut(duration: 0.16), value: isHoveringFullscreenControlsRegion)
    }
  }

  private var controlsView: some View {
    let hasActiveMedia = viewModel.currentURL != nil

    return HStack(spacing: 8) {
      PlaybackTransportButtons(
        isPlaying: displayedIsPlaying,
        isEnabled: hasActiveMedia,
        usesSpaceShortcut: true,
        onPlayPause: viewModel.togglePlayPause,
        onSkipBackward: viewModel.skipBackward,
        onSkipForward: viewModel.skipForward
      )

      HStack(spacing: 8) {
        Text(displayedCurrentTime.playbackText)
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.primary)
          .frame(width: 52, alignment: .leading)

        seekBar

        Text(viewModel.playbackState.duration.playbackText)
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.primary)
          .frame(width: 52, alignment: .trailing)
      }
      .frame(maxWidth: .infinity)

      Button {
        isVolumePopoverPresented.toggle()
      } label: {
        Image(systemName: "speaker.wave.2.fill")
      }
      .buttonStyle(.bordered)
      .help("Volume")
      .popover(isPresented: $isVolumePopoverPresented, arrowEdge: .top) {
        volumePopoverContent
      }

      Menu {
        ForEach(playbackRateOptions, id: \.self) { rate in
          Button {
            viewModel.playbackRate = rate
          } label: {
            HStack(spacing: 8) {
              Text(playbackRateLabel(for: rate))

              Spacer(minLength: 8)

              if isSelectedPlaybackRate(rate) {
                Image(systemName: "checkmark")
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      } label: {
        Text(playbackRateLabel(for: viewModel.playbackRate))
          .font(.system(.footnote, design: .monospaced))
          .frame(minWidth: 42)
      }
      .buttonStyle(.bordered)
      .help("Playback Speed")
      .disabled(!hasActiveMedia)

      Menu {
        Button("Open...") {
          viewModel.openPanel()
        }

        Divider()

        Button(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
          isSidebarVisible.toggle()
        }
        .keyboardShortcut("b", modifiers: .command)

        Divider()

        Button("Add Subtitle...") {
          viewModel.openSubtitlePanel()
        }

        if viewModel.hasSubtitleTrack {
          Button(viewModel.subtitlesEnabled ? "Hide Subtitles" : "Show Subtitles") {
            viewModel.subtitlesEnabled.toggle()
          }

          Button("Remove Subtitle") {
            viewModel.removeSubtitleTrack()
          }
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .buttonStyle(.bordered)
      .help("More Actions")

      Button(action: toggleFullscreen) {
        Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
      }
      .buttonStyle(.bordered)
      .help(isFullscreen ? "Exit Full Screen" : "Enter Full Screen")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    }
  }

  private var volumePopoverContent: some View {
    let trailingControlWidth: CGFloat = 44

    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Volume")
          .font(.subheadline.weight(.semibold))

        Spacer(minLength: 8)

        Button {
          viewModel.isMuted.toggle()
        } label: {
          Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
        .buttonStyle(.bordered)
        .frame(width: trailingControlWidth, alignment: .trailing)
        .help(viewModel.isMuted ? "Unmute" : "Mute")
      }

      HStack(spacing: 10) {
        Image(systemName: "speaker.wave.1.fill")
          .foregroundStyle(.secondary)

        Slider(value: $viewModel.volume, in: 0...1)
          .frame(maxWidth: .infinity)
          .disabled(viewModel.isMuted)
          .onChange(of: viewModel.volume) { newValue in
            if newValue > 0, viewModel.isMuted {
              viewModel.isMuted = false
            }
          }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .frame(width: 272)
  }

  private var headerView: some View {
    HStack(spacing: 12) {
      Text(viewModel.currentURL?.lastPathComponent ?? "Open a local video to start playback")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    }
  }

  private var backgroundLayer: some View {
    Group {
      if isFullscreen {
        Color.black
      } else {
        LinearGradient(
          colors: [
            Color(red: 0.07, green: 0.1, blue: 0.14),
            Color(red: 0.11, green: 0.15, blue: 0.2)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
    }
    .ignoresSafeArea()
  }

  private var seekBar: some View {
    GeometryReader { geometry in
      let width = max(geometry.size.width, 1)
      let duration = max(viewModel.playbackState.duration, 0)
      let currentTime = displayedCurrentTime
      let playedRatio = normalizedSeekRatio(for: currentTime, duration: duration)
      let markerX = min(max(width * playedRatio, 0), width)
      let previewTime = isSeeking ? seekPosition : nil
      let previewPadding = min(CGFloat(28), width / 2)
      let previewCenterX = min(max(markerX, previewPadding), width - previewPadding)

      ZStack(alignment: .leading) {
        Capsule(style: .continuous)
          .fill(.white.opacity(0.2))
          .frame(height: 4)

        Capsule(style: .continuous)
          .fill(.white.opacity(0.88))
          .frame(width: max(width * playedRatio, 4), height: 4)

        Circle()
          .fill(.white)
          .frame(width: 10, height: 10)
          .offset(x: max(markerX - 5, 0))

        if let previewTime {
          Text(previewTime.playbackText)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .position(x: previewCenterX, y: -8)
        }
      }
      .frame(height: 22)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard duration > 0 else { return }
            let clampedX = min(max(value.location.x, 0), width)

            let targetTime = seekTime(for: clampedX, totalWidth: width)
            if !isSeeking {
              beginSeekingSession()
            }

            seekPosition = targetTime
          }
          .onEnded { value in
            guard duration > 0 else {
              endSeekingSession()
              return
            }

            let clampedX = min(max(value.location.x, 0), width)
            let targetTime = seekTime(for: clampedX, totalWidth: width)
            seekPosition = targetTime
            viewModel.seek(to: targetTime, persistImmediately: true)
            endSeekingSession()
          }
      )
      .opacity(duration > 0 ? 1 : 0.5)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 22)
  }

  private func normalizedSeekRatio(for time: Double, duration: Double) -> Double {
    MediaTime(seconds: time).ratio(toDuration: duration)
  }

  private func seekTime(for positionX: CGFloat, totalWidth: CGFloat) -> Double {
    let ratio = Double(positionX / max(totalWidth, 1))
    return MediaTime.seconds(forRatio: ratio, duration: viewModel.playbackState.duration)
  }

  private var displayedCurrentTime: TimeInterval {
    isSeeking ? seekPosition : viewModel.playbackState.currentTime
  }

  private var displayedIsPlaying: Bool {
    isSeeking ? seekStartedWhilePlaying : viewModel.playbackState.isPlaying
  }

  private func beginSeekingSession() {
    isSeeking = true
    seekStartedWhilePlaying = viewModel.playbackState.isPlaying
  }

  private func endSeekingSession() {
    isSeeking = false
  }

  private var dropIndicator: some View {
    Label("Drop to Open", systemImage: "arrow.down.doc")
      .font(.headline)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .foregroundStyle(.white)
      .background(.blue.opacity(0.8), in: Capsule())
      .padding(14)
  }

  private func handleDrop(providers: [NSItemProvider]) -> Bool {
    DropURLLoader.loadFirstURL(from: providers) { url in
      guard let url else { return }
      viewModel.open(url: url)
    }
  }

  private func setupKeyboardMonitoring() {
    guard keyboardMonitor == nil else {
      return
    }

    keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard self.currentWindow() != nil else {
        return event
      }

      guard !event.modifierFlags.contains(.command) else {
        // Handle Cmd+B for sidebar toggle
        if event.keyCode == 11 {
          self.isSidebarVisible.toggle()
          return nil
        }
        return event
      }

      if event.keyCode == 53 {
        self.exitFullScreenIfNeeded()
        return nil
      }

      guard self.viewModel.currentURL != nil else {
        return event
      }

      switch event.keyCode {
      case 49:
        self.viewModel.togglePlayPause()
        return nil
      case 123:
        self.viewModel.skipBackward()
        return nil
      case 124:
        self.viewModel.skipForward()
        return nil
      default:
        return event
      }
    }
  }

  private func teardownKeyboardMonitoring() {
    if let monitor = keyboardMonitor {
      NSEvent.removeMonitor(monitor)
      keyboardMonitor = nil
    }
  }

  private func exitFullScreenIfNeeded() {
    guard
      let window = currentWindow(),
      window.styleMask.contains(.fullScreen)
    else {
      return
    }

    window.toggleFullScreen(nil)
  }

  private func toggleFullscreen() {
    currentWindow()?.toggleFullScreen(nil)
  }

  private func syncFullscreenState(from window: NSWindow? = nil) {
    if let window {
      isFullscreen = window.styleMask.contains(.fullScreen)
      return
    }

    isFullscreen = currentWindow()?.styleMask.contains(.fullScreen) ?? false
  }

  private func currentWindow() -> NSWindow? {
    NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow
  }

  private func updateFullscreenDependentState(isFullscreen: Bool) {
    if isFullscreen {
      fullscreenCursorAutoHideController.start(window: currentWindow())
    } else {
      fullscreenCursorAutoHideController.stop()
      isHoveringFullscreenControlsRegion = false
      resetFullscreenSubtitlePanelState()
    }
  }

  private func updateFullscreenSubtitleHotspotHover(_ hovering: Bool) {
    handleFullscreenSubtitle(effect: fullscreenSubtitlePanel.hotspotHoverChanged(hovering))
  }

  private func updateFullscreenSubtitlePanelHover(_ hovering: Bool) {
    handleFullscreenSubtitle(effect: fullscreenSubtitlePanel.panelHoverChanged(hovering))
  }

  private func handleFullscreenSubtitle(effect: FullscreenSubtitlePanelVisibility.HoverEffect) {
    switch effect {
    case .show:
      cancelFullscreenSubtitleHide()
    case .scheduleHide:
      scheduleFullscreenSubtitlePanelHide()
    }
  }

  private func cancelFullscreenSubtitleHide() {
    fullscreenSubtitleHideWorkItem?.cancel()
    fullscreenSubtitleHideWorkItem = nil
  }

  private func scheduleFullscreenSubtitlePanelHide() {
    fullscreenSubtitleHideWorkItem?.cancel()

    let workItem = DispatchWorkItem {
      fullscreenSubtitlePanel.hideIfIdle()
    }

    fullscreenSubtitleHideWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + fullscreenSubtitleHideDelay, execute: workItem)
  }

  private func resetFullscreenSubtitlePanelState() {
    cancelFullscreenSubtitleHide()
    fullscreenSubtitlePanel.reset()
  }

  private func playbackRateLabel(for rate: Double) -> String {
    switch rate {
    case 0.5:
      return "0.5x"
    case 1.0:
      return "1.0x"
    case 1.25:
      return "1.25x"
    case 1.5:
      return "1.5x"
    case 2.0:
      return "2.0x"
    default:
      return String(format: "%.2fx", rate)
    }
  }

  private func isSelectedPlaybackRate(_ rate: Double) -> Bool {
    abs(rate - viewModel.playbackRate) < 0.001
  }
}
