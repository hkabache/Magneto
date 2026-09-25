import SwiftUI

@main
struct MagnetoIOSApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var dictation = Dictation.shared

    var body: some Scene {
        WindowGroup {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(dictation)
        }
    }
}
