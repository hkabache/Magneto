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

    private init() {
        overlayPosition = OverlayPosition(rawValue: defaults.string(forKey: "overlayPosition") ?? "") ?? .bottom
        postProcessEnabled = defaults.object(forKey: "postProcessEnabled") as? Bool ?? true
        postProcessProvider = PostProcessProvider(rawValue: defaults.string(forKey: "postProcessProvider") ?? "") ?? .mistral
        aggressiveFillers = defaults.bool(forKey: "aggressiveFillers")
        frenchTypography = defaults.object(forKey: "frenchTypography") as? Bool ?? true
        customWords = defaults.stringArray(forKey: "customWords") ?? []
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
