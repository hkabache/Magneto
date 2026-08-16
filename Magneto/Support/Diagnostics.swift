import Foundation
import OSLog

enum Diagnostics {
    /// Bounded by a count rather than by a time window: someone who dictated twice in
    /// the morning and reports the problem at noon would get an empty window back, and
    /// an empty report reads like "nothing went wrong" instead of "look further back".
    private static let maximumEntries = 300

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Read back out of the unified log rather than from a buffer of our own, so the
    /// entries survive whatever went wrong. Nothing is transmitted: the report reaches
    /// the clipboard, and only the user decides where it goes next.
    static func report() async -> String {
        await Task.detached(priority: .userInitiated) { collect() }.value
    }

    private static func collect() -> String {
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        var lines = ["Magneto \(appVersion) · macOS \(system)"]
        do {
            // Reading the whole system store needs an entitlement Apple does not grant.
            // This scope is the one an app may always read, and it covers the current
            // launch, which for a menu bar app is usually days.
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(
                matching: NSPredicate(format: "subsystem == %@", Log.subsystem)
            ).compactMap { $0 as? OSLogEntryLog }

            if entries.isEmpty {
                lines.append("Aucune dictée depuis le lancement de l'app.")
            } else {
                if entries.count > maximumEntries {
                    lines.append("(\(entries.count - maximumEntries) lignes plus anciennes omises)")
                }
                lines.append(contentsOf: entries.suffix(maximumEntries).map(format))
            }
        } catch {
            lines.append("Journal illisible : \(error.localizedDescription)")
        }
        return lines.joined(separator: "\n")
    }

    private static func format(_ entry: OSLogEntryLog) -> String {
        let time = entry.date.formatted(.dateTime.hour().minute().second())
        let marker = entry.level == .error || entry.level == .fault ? "!" : " "
        return "\(time) \(marker) [\(entry.category)] \(entry.composedMessage)"
    }
}
