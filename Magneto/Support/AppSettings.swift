import Foundation
import SwiftUI

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

enum PostProcessProvider: String, CaseIterable, Identifiable {
    case mistral, anthropic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mistral: return "Mistral Small"
        case .anthropic: return "Claude Haiku"
        }
    }

    var keychainAccount: String {
        switch self {
        case .mistral: return Keychain.mistral
        case .anthropic: return Keychain.anthropic
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var overlayPosition: OverlayPosition {
        didSet { defaults.set(overlayPosition.rawValue, forKey: "overlayPosition") }
    }
    @Published var capsLockNoDelay: Bool {
        didSet {
            defaults.set(capsLockNoDelay, forKey: "capsLockNoDelay")
            CapsLockDelay.apply(noDelay: capsLockNoDelay)
        }
    }
    @Published var postProcessEnabled: Bool {
        didSet { defaults.set(postProcessEnabled, forKey: "postProcessEnabled") }
    }
    @Published var postProcessProvider: PostProcessProvider {
        didSet { defaults.set(postProcessProvider.rawValue, forKey: "postProcessProvider") }
    }
    @Published var aggressiveFillers: Bool {
        didSet { defaults.set(aggressiveFillers, forKey: "aggressiveFillers") }
    }
    @Published var frenchTypography: Bool {
        didSet { defaults.set(frenchTypography, forKey: "frenchTypography") }
    }
    @Published var customWords: [String] {
        didSet { defaults.set(customWords, forKey: "customWords") }
    }

    let language = "fr"

    /// Names that are the same for every user, and that dictating about Magneto
    /// itself keeps getting wrong. Kept out of the Vocabulaire tab: nobody should
    /// have to type them, and nobody has a reason to remove them.
    private static let builtInWords = [
        "Magneto", "ElevenLabs", "Voxtral", "Mistral", "Anthropic", "Claude", "Haiku",
    ]

    /// User terms first: the keyterms list is capped, and someone's own words matter
    /// more than the engine names if that cap is ever reached.
    var vocabulary: [String] {
        var seen = Set<String>()
        return (customWords + Self.builtInWords).filter { seen.insert($0.lowercased()).inserted }
    }

    private init() {
        overlayPosition = OverlayPosition(rawValue: defaults.string(forKey: "overlayPosition") ?? "") ?? .bottom
        capsLockNoDelay = defaults.bool(forKey: "capsLockNoDelay")
        postProcessEnabled = defaults.object(forKey: "postProcessEnabled") as? Bool ?? true
        postProcessProvider = PostProcessProvider(rawValue: defaults.string(forKey: "postProcessProvider") ?? "") ?? .mistral
        aggressiveFillers = defaults.bool(forKey: "aggressiveFillers")
        frenchTypography = defaults.object(forKey: "frenchTypography") as? Bool ?? true
        customWords = defaults.stringArray(forKey: "customWords") ?? []

        // The HID override dies with the login session and `didSet` never fires from
        // `init`, so an enabled option has to be re-applied here at every launch.
        // Left untouched when disabled: no reason to write a system property that
        // was never asked for.
        if capsLockNoDelay {
            CapsLockDelay.apply(noDelay: true)
        }
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
