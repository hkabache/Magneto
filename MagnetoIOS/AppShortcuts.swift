import AppIntents

/// Exposes the intent to Shortcuts, Siri and the Action button. The Action button and
/// Back Tap run shortcuts, and the Dicter shortcut wraps this intent with the copy step.
struct MagnetoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: ["Dicter avec \(.applicationName)"],
            shortTitle: "Dicter",
            systemImageName: "mic.fill"
        )
    }
}
