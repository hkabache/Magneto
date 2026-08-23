import AppKit
import Combine
import Sparkle

/// Sparkle is wired for a manual check and nothing else: `SUEnableAutomaticChecks` is
/// false in the Info.plist, so no request leaves the Mac until the button is pressed.
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var canCheck = false

    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    /// Sparkle answers in a window, and an app without a Dock icon does not come
    /// forward on its own: without this, the answer would open behind whatever the
    /// user is looking at, and the click would seem to have done nothing.
    func check() {
        NSApp.activate()
        controller.updater.checkForUpdates()
    }
}
