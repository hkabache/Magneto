import SwiftUI

@main
struct MagnetoApp: App {
    @StateObject private var app = AppState.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var updater = Updater()

    /// The Debug build keeps a Dock icon: Claude Code's computer use only offers running
    /// apps that have one, so a menu bar app without it cannot be tested on screen.
    /// Dropping `LSUIElement` for a runtime `.accessory` was tried and changed nothing.
    init() {
        #if DEBUG
        NSApplication.shared.setActivationPolicy(.regular)
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
                .environmentObject(settings)
                .environmentObject(updater)
        } label: {
            Image(systemName: app.phase.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
