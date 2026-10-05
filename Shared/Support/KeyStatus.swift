import Foundation

/// One probe per key per session, the verdict kept for the session, shared by the Mac
/// popover and the iPhone screen so a key lights up the same way on both.
@MainActor
final class KeyStatus: ObservableObject {
    @Published private(set) var present: Set<String> = []
    @Published private(set) var checking: Set<String> = []
    struct Problem {
        let message: String
        /// A refused key needs a new one, an exhausted quota needs patience. Sending
        /// someone to re-paste a perfectly good key helps nobody.
        let blocking: Bool
    }

    @Published private(set) var problems: [String: Problem] = [:]
    /// Only keys actually probed in this session. Reopening the tab reloads presence
    /// but probes nothing, and a green tick claiming validity would then be a guess.
    @Published private(set) var validated: Set<String> = []

    private static let accounts = [Keychain.microsoft, Keychain.elevenLabs]

    /// Probes anything still without a verdict, so opening the tab is enough to know
    /// where each key stands. A verdict is kept for the whole session, so this costs
    /// one request per key per launch. A previous failure is retried, since it may
    /// have been the network rather than the key.
    func load() {
        present = Set(Self.accounts.filter { Keychain.exists($0) })
        for account in present where !validated.contains(account) && !checking.contains(account) {
            guard let key = Keychain.get(account) else { continue }
            Task { await verify(key, account: account) }
        }
    }

    func save(_ key: String, account: String, label: String) async {
        Keychain.set(key, account: account, label: label)
        // A keychain that refuses the write says nothing on its own, and a field that
        // simply empties itself looks like a key that was saved.
        guard Keychain.exists(account) else {
            problems[account] = Problem(message: "Clé non enregistrée dans le trousseau", blocking: true)
            return
        }
        present.insert(account)
        await verify(key, account: account)
    }

    /// The verdict goes with the key: a tick left behind would claim a key that is gone.
    func remove(_ account: String) {
        Keychain.delete(account)
        present.remove(account)
        validated.remove(account)
        problems[account] = nil
    }

    private func verify(_ key: String, account: String) async {
        problems[account] = nil
        validated.remove(account)
        checking.insert(account)
        let outcome = await KeyCheck.run(account: account, key: key)
        checking.remove(account)
        switch outcome {
        case .valid:
            validated.insert(account)
        case .unusable(let reason):
            problems[account] = Problem(message: reason, blocking: false)
        case .refused(let reason):
            problems[account] = Problem(message: reason, blocking: true)
        }
    }
}
