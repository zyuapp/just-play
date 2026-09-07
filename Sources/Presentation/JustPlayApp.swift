import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let updateController = UpdateController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    updateController.start()
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    AppOpenBus.post(urls: urls)
  }
}

@main
struct JustPlayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .commands {
      CommandGroup(after: .appInfo) {
        CheckForUpdatesButton(controller: appDelegate.updateController)
      }
      CommandGroup(after: .newItem) {
        Button("Open...") {
          VideoOpenPanel.present()
        }
        .keyboardShortcut("o", modifiers: [.command])
      }
    }
  }
}

private struct CheckForUpdatesButton: View {
  @ObservedObject var controller: UpdateController

  var body: some View {
    Button("Check for Updates…") {
      controller.checkForUpdates()
    }
    .disabled(!controller.canCheckForUpdates)
  }
}
