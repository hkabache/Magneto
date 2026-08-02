import SwiftUI

@main
struct MagnetoApp: App {
    @StateObject private var app = AppState.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
                .environmentObject(settings)
        } label: {
            Image(systemName: app.phase.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
