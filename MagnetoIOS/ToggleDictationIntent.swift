import AppIntents

/// Both protocols, on purpose. LiveActivityIntent is what lets the system launch the app
/// in the background and accept a Live Activity started from perform(), and
/// AudioRecordingIntent declares that this process is about to record. The two public
/// attempts at background dictation that failed each lacked one of them.
struct ToggleDictationIntent: AppIntent, AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Dicter"
    static let description = IntentDescription("Démarre la dictée, ou l'arrête et rend le texte transcrit.")
    static let supportedModes: IntentModes = .background

    /// The text is returned rather than copied: a process launched in the background has
    /// no access to the pasteboard, the write is dropped without an error. The Dicter
    /// shortcut copies the value, which Shortcuts may do from anywhere. Nil on the press
    /// that starts a dictation, so the shortcut's "has any value" test skips the copy.
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        .result(value: await Dictation.shared.toggle())
    }
}
