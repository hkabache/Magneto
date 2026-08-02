import Foundation

enum HandyMigration {
    @MainActor
    static func runIfNeeded(settings: AppSettings) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "handyMigrationDone") else { return }
        defaults.set(true, forKey: "handyMigrationDone")

        let path = ("~/Library/Application Support/com.pais.handy/settings_store.json" as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let handy = root["settings"] as? [String: Any]
        else { return }

        if settings.customWords.isEmpty, let words = handy["custom_words"] as? [String] {
            settings.customWords = words.filter { !$0.isEmpty }
        }
        if !Keychain.exists(Keychain.mistral),
           let key = handy["cloud_transcription_api_key"] as? String, !key.isEmpty {
            Keychain.set(key, account: Keychain.mistral)
        }
        if !Keychain.exists(Keychain.anthropic),
           let key = handy["anthropic_api_key"] as? String, !key.isEmpty {
            Keychain.set(key, account: Keychain.anthropic)
        }
    }
}
