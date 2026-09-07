import Combine
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
  @Published private(set) var canCheckForUpdates = false

  private let controller: SPUStandardUpdaterController

  init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: false,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    controller.updater.publisher(for: \.canCheckForUpdates)
      .receive(on: DispatchQueue.main)
      .assign(to: &$canCheckForUpdates)
  }

  func start() {
    controller.startUpdater()
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}
