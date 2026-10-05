import Foundation
import SwiftUI

#if os(macOS)
enum OverlayPosition: String, CaseIterable, Identifiable {
    case top, bottom, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: return "En haut"
        case .bottom: return "En bas"
        case .none: return "Masquée"
        }
    }
}
#endif

/// One settings object for both apps. The two macOS-only settings stay here under a
/// condition rather than in a subclass: they are two properties, and every screen that
/// reads settings keeps a single type to talk to.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    #if os(macOS)
    @Published var overlayPosition: OverlayPosition {
        didSet { defaults.set(overlayPosition.rawValue, forKey: "overlayPosition") }
    }
    @Published var capsLockNoDelay: Bool {
        didSet {
            defaults.set(capsLockNoDelay, forKey: "capsLockNoDelay")
            CapsLockDelay.apply(noDelay: capsLockNoDelay)
        }
    }
    #endif
    @Published var straightQuotes: Bool {
        didSet { defaults.set(straightQuotes, forKey: "straightQuotes") }
    }
    @Published var dictationJournal: Bool {
        didSet { defaults.set(dictationJournal, forKey: "dictationJournal") }
    }
    @Published var engineChoice: EngineChoice {
        didSet { defaults.set(engineChoice.rawValue, forKey: "engineChoice") }
    }
    @Published var customWords: [String] {
        didSet { defaults.set(customWords, forKey: "customWords") }
    }

    let language = "fr"

    /// Names that are the same for every user, and that dictating about Magneto
    /// itself keeps getting wrong. Kept out of the Vocabulaire tab: nobody should
    /// have to type them, and nobody has a reason to remove them.
    private static let builtInWords = [
        "Magneto", "ElevenLabs",
    ]

    /// User terms first: the keyterms list is capped, and someone's own words matter
    /// more than the engine names if that cap is ever reached.
    var vocabulary: [String] {
        var seen = Set<String>()
        return (customWords + Self.builtInWords).filter { seen.insert($0.lowercased()).inserted }
    }

    private init() {
        #if os(macOS)
        overlayPosition = OverlayPosition(rawValue: defaults.string(forKey: "overlayPosition") ?? "") ?? .bottom
        capsLockNoDelay = defaults.bool(forKey: "capsLockNoDelay")
        #endif
        straightQuotes = defaults.object(forKey: "straightQuotes") as? Bool ?? true
        dictationJournal = defaults.bool(forKey: "dictationJournal")
        customWords = defaults.stringArray(forKey: "customWords") ?? []
        // Scribe's text is the cleaner, MAI-Transcribe-2's the faster by far: the race
        // keeps the first whenever it comes back in time, on both devices.
        engineChoice = EngineChoice(rawValue: defaults.string(forKey: "engineChoice") ?? "") ?? .race

        #if os(macOS)
        // The HID override dies with the login session and `didSet` never fires from
        // `init`, so an enabled option has to be re-applied here at every launch.
        // Left untouched when disabled: no reason to write a system property that
        // was never asked for.
        if capsLockNoDelay {
            CapsLockDelay.apply(noDelay: true)
        }
        #endif
    }

    func addCustomWord(_ word: String) {
        let cleaned = word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !"<>{}[]\\".contains($0) }
        guard !cleaned.isEmpty, cleaned.count < 50 else { return }
        guard !customWords.contains(where: { $0.lowercased() == cleaned.lowercased() }) else { return }
        customWords.append(cleaned)
    }

    func removeCustomWord(_ word: String) {
        customWords.removeAll { $0 == word }
    }
}
