import Foundation

/// Dictations and what the cloud engines billed for them, added up by month. Numbers
/// only: nothing here says what was dictated.
struct Usage: Codable, Equatable {
    var dictations = 0
    /// Audio dictated, counted once even when the race sends it to both engines.
    var seconds: TimeInterval = 0
    /// Dollars per engine, priced when the request answered, so a price change never
    /// rewrites a past month.
    var costs: [String: Double] = [:]

    var cost: Double {
        costs.values.reduce(0, +)
    }

    func cost(of engine: Engine) -> Double {
        costs[engine.rawValue] ?? 0
    }

    /// "12 dictées · 0,05 $". Cents matter at this scale, and "0,00 $" for a few
    /// dictations would read as free.
    var summary: String {
        "\(dictations) dictée\(dictations > 1 ? "s" : "") · \(Self.dollars(cost))"
    }

    /// "8 min d'audio · ElevenLabs 0,03 $ · Microsoft 0,02 $", the engines that cost something.
    var detail: String {
        let minutes = Int((seconds / 60).rounded())
        let engines = Engine.allCases
            .filter { cost(of: $0) > 0 }
            .map { "\($0.label) \(Self.dollars(cost(of: $0)))" }
        return (["\(minutes) min d'audio"] + engines).joined(separator: " · ")
    }

    /// Shown on both platforms, the prices read from `Engine` so the text follows them.
    static var explanation: String {
        let prices = Engine.allCases
            .map { "\($0.label) \(dollars($0.pricePerHour, exact: true)) de l'heure" }
            .joined(separator: ", ")
        return """
        La durée de chaque dictée au tarif public : \(prices).

        En course, les deux moteurs sont facturés.

        Pour la consommation réelle, rendez-vous sur l'interface du fournisseur.
        """
    }

    static func dollars(_ value: Double, exact: Bool = false) -> String {
        if !exact, value > 0, value < 0.01 {
            return "< 0,01 $"
        }
        return value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "fr_FR"))) + " $"
    }
}

@MainActor
final class UsageLedger: ObservableObject {
    static let shared = UsageLedger()

    /// Keyed "2026-10". Never reset: this and last month always come from here.
    @Published private(set) var months: [String: Usage]
    /// Counted since `since`, which the reset button moves to today.
    @Published private(set) var sinceReset: Usage
    @Published private(set) var since: Date

    private let defaults = UserDefaults.standard

    private init() {
        months = Self.load([String: Usage].self, key: "usage") ?? [:]
        sinceReset = Self.load(Usage.self, key: "usageSinceReset") ?? Usage()
        if let start = defaults.object(forKey: "usageSince") as? Date {
            since = start
        } else {
            since = Date()
            defaults.set(since, forKey: "usageSince")
        }
    }

    var thisMonth: Usage { months[Self.key(for: Date())] ?? Usage() }

    var lastMonth: Usage {
        let calendar = Calendar(identifier: .gregorian)
        guard let previous = calendar.date(byAdding: .month, value: -1, to: Date()) else { return Usage() }
        return months[Self.key(for: previous)] ?? Usage()
    }

    /// One dictation sent to at least one cloud engine.
    func recordDictation(seconds: TimeInterval) {
        update { usage in
            usage.dictations += 1
            usage.seconds += seconds
        }
    }

    /// One request the engine answered, so one it billed, the race's loser included.
    func charge(_ engine: Engine, seconds: TimeInterval) {
        let cost = seconds * engine.pricePerHour / 3600
        update { usage in
            usage.costs[engine.rawValue, default: 0] += cost
        }
    }

    /// Starts the running total over from today. The months are kept.
    func reset() {
        sinceReset = Usage()
        since = Date()
        defaults.set(since, forKey: "usageSince")
        save()
    }

    private func update(_ change: (inout Usage) -> Void) {
        let key = Self.key(for: Date())
        var month = months[key] ?? Usage()
        change(&month)
        months[key] = month
        change(&sinceReset)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(months) {
            defaults.set(data, forKey: "usage")
        }
        if let data = try? JSONEncoder().encode(sinceReset) {
            defaults.set(data, forKey: "usageSinceReset")
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    nonisolated static func key(for date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}
