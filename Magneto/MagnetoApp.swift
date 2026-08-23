import SwiftUI

@main
struct MagnetoApp: App {
    @StateObject private var app = AppState.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var updater = Updater()

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
