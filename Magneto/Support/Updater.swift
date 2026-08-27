import AppKit
import Combine
import Sparkle

/// Sparkle looks for a new version on its own, and never opens a window to say it
/// found one: `pendingVersion` carries the news to the popover, which is where a
/// menu bar app can speak without interrupting. Installing stays a click.
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var canCheck = false
    /// The version a scheduled check found, and that no window has announced yet.
    @Published private(set) var pendingVersion: String?

    private let controller: SPUStandardUpdaterController
    private let reminders: GentleReminders

    init() {
        let reminders = GentleReminders()
        self.reminders = reminders
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: reminders
        )
        reminders.updater = self
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    /// Sparkle answers in a window, and an app without a Dock icon does not come
    /// forward on its own: without this, the answer would open behind whatever the
    /// user is looking at, and the click would seem to have done nothing.
    func check() {
        NSApp.activate()
        controller.updater.checkForUpdates()
    }

    fileprivate func announce(_ version: String?) {
        pendingVersion = version
    }
}

/// Its own object rather than the updater itself: the protocol is Objective-C and
/// carries no isolation, so satisfying it from a `@MainActor` class costs a warning
/// on every method.
///
/// Sparkle calls these by selector, and they are all optional, so a method Swift
/// renames is a method Sparkle silently stops calling. `UpdaterTests` pins them.
final class GentleReminders: NSObject, SPUStandardUserDriverDelegate {
    /// Assigned as soon as the updater exists, which cannot happen before the
    /// controller this object is handed to.
    weak var updater: Updater?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// A window that opens by itself takes the focus, and with it the synthesized
    /// Cmd+V of a dictation still in flight. A scheduled check therefore shows
    /// nothing at all: it hands the version over, and the window waits for a click.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // True for a check the user asked for, which Sparkle shows itself.
        guard !handleShowingUpdate else { return }
        announce(update.displayVersionString)
    }

    /// The update reached a window, so the popover has nothing left to announce.
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        announce(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        announce(nil)
    }

    private func announce(_ version: String?) {
        let updater = updater
        Task { @MainActor in
            updater?.announce(version)
        }
    }
}
