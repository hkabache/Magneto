import Foundation

protocol TranscriptionClient {
    var name: String { get }
    func transcribe(audioURL: URL, language: String, vocabulary: [String]) async throws -> String
}

struct Multipart {
    let boundary = "magneto-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    mutating func addField(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data("\(value)\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, mime: String, data: Data) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finalized() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }
}

enum HTTP {
    static func send(_ request: URLRequest, body: Data, retries: Int = 2) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await URLSession.shared.upload(for: request, from: body)
                guard let http = response as? HTTPURLResponse else {
                    throw MagnetoError.timeout
                }
                if http.statusCode == 429 || http.statusCode >= 500, attempt < retries {
                    attempt += 1
                    try await Task.sleep(for: .milliseconds(500 * attempt))
                    continue
                }
                return (data, http)
            } catch let error as URLError where error.code == .timedOut && attempt < retries {
                attempt += 1
                try await Task.sleep(for: .milliseconds(500 * attempt))
            }
        }
    }

    static func errorBody(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "réponse illisible"
        return String(text.prefix(300))
    }
}

/// What the user picks: one engine first, or both at once.
enum EngineChoice: String, CaseIterable, Identifiable {
    case race, microsoft, elevenLabs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .race: return "Course"
        case .microsoft: return Engine.microsoft.label
        case .elevenLabs: return Engine.elevenLabs.label
        }
    }

    /// Shown on both platforms. The figures come from `Race` so the text cannot drift
    /// from the rule again, as it did when the long-audio exception was added.
    static var explanation: String {
        let deadline = Double(Race.deadline.components.seconds)
            + Double(Race.deadline.components.attoseconds) / 1e18
        let seconds = deadline.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR")))
        return """
        Course : les deux moteurs reçoivent la dictée. Le texte d'ElevenLabs est gardé s'il arrive en moins de \(seconds) s, sinon celui de Microsoft. Au-delà de \(Int(Race.longAudio)) s d'audio, Microsoft est pris dès qu'il répond.

        Microsoft ou ElevenLabs : ce moteur est essayé en premier, l'autre prend le relais s'il échoue.

        Le moteur Apple hors ligne passe en dernier.
        """
    }

    /// The engine tried first when the choice is not a race, or when the race lacks a key.
    var primary: Engine {
        switch self {
        case .race, .elevenLabs: return .elevenLabs
        case .microsoft: return .microsoft
        }
    }
}

/// The cloud engines, one per key. Apple is not among them: it needs no key and always
/// answers last, so it is never a choice.
enum Engine: String, CaseIterable, Identifiable {
    case microsoft, elevenLabs

    var id: String { rawValue }

    /// The provider alone, as on the key fields: the model name wrapped the iPhone row
    /// onto two lines.
    var label: String {
        switch self {
        case .microsoft: return "Microsoft"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    var account: String {
        switch self {
        case .microsoft: return Keychain.microsoft
        case .elevenLabs: return Keychain.elevenLabs
        }
    }

    /// Public prices in dollars per hour of audio, checked in October 2026. Scribe v2 is
    /// 0.22 plus 0.05 for keyterms, always sent since the built-in words never leave the
    /// list. MAI-Transcribe-2's 0.10 is a launch price announced until December 31, 2026,
    /// with nothing published for after: to revisit then.
    var pricePerHour: Double {
        switch self {
        case .microsoft: return 0.10
        case .elevenLabs: return 0.27
        }
    }

    fileprivate var client: any TranscriptionClient {
        switch self {
        case .microsoft: return MicrosoftClient()
        case .elevenLabs: return ElevenLabsClient()
        }
    }

    /// The chosen engine first, the others behind it in their declared order, and only
    /// those with a key.
    static func order(primary: Engine, available: Set<Engine>) -> [Engine] {
        ([primary] + allCases.filter { $0 != primary }).filter(available.contains)
    }
}

/// Both engines sent the same audio at once, Scribe preferred for its cleaner text and
/// MAI-Transcribe-2 kept for when Scribe is slow. Scribe answers a dictation in 1.2 s at
/// the median but took over two seconds once in four, up to 4.5 s, over a week of real
/// use; MAI answered every one of its dictations within 1.1 s.
///
/// Fed one event at a time, it says whether to keep waiting. Pure, so the rules are
/// tested without a network.
struct Race {
    enum Attempt: Equatable {
        case text(String)
        case failed(String)

        var text: String? {
            if case .text(let text) = self { return text }
            return nil
        }
    }

    enum Verdict: Equatable {
        case wait, preferred, fallback, bothFailed
    }

    /// 64 % of last week's Scribe dictations came back within it: those keep Scribe's
    /// text, the rest get MAI's without waiting further.
    static let deadline = Duration.milliseconds(1500)

    /// Scribe's time grows with the audio, MAI's barely does. Over a morning of races on
    /// the Mac, Scribe won every dictation of 16 s or less and missed the deadline on
    /// every one from 23 s; on the iPhone the line sat between 34 and 41 s. Past this
    /// length, waiting out the deadline only delays MAI's text, so there is no deadline.
    /// Set above both lines on purpose: if Scribe gets faster, the late times it keeps
    /// logging will show it.
    static let longAudio: TimeInterval = 45

    static func deadline(forAudio seconds: TimeInterval) -> Duration {
        seconds > longAudio ? .zero : deadline
    }

    var preferred: Attempt?
    var fallback: Attempt?
    var deadlinePassed = false

    var verdict: Verdict {
        if preferred?.text != nil {
            return .preferred
        }
        if fallback?.text != nil, deadlinePassed || preferred != nil {
            return .fallback
        }
        if preferred != nil, fallback != nil {
            return .bothFailed
        }
        return .wait
    }
}

enum TranscriptionService {
    typealias Transcription = (text: String, engine: String, failures: [String])

    /// Failures are reported alongside a success, not only when everything fails: a
    /// primary engine that dies and leaves a lesser one to answer used to be entirely
    /// invisible, so the quality dropped without a word.
    static func transcribe(
        audioURL: URL,
        language: String,
        vocabulary: [String],
        choice: EngineChoice
    ) async -> Result<Transcription, MagnetoError> {
        let available = Set(Engine.allCases.filter { Keychain.exists($0.account) })
        // Read before the first suspension, like the audio itself: the file may be gone
        // once a text is chosen.
        let seconds = AudioFile.duration(of: audioURL)
        var failures: [String] = []
        var clients: [(client: any TranscriptionClient, billed: Engine?)] = []

        if !available.isEmpty {
            await UsageLedger.shared.recordDictation(seconds: seconds)
        }
        if choice == .race, available == Set(Engine.allCases) {
            let outcome = await race(audioURL: audioURL, seconds: seconds, language: language, vocabulary: vocabulary)
            failures = outcome.failures
            if let winner = outcome.winner {
                return .success((winner.text, winner.engine, failures))
            }
        } else {
            clients = Engine.order(primary: choice.primary, available: available).map { ($0.client, $0) }
        }
        clients.append((AppleSpeechClient(), nil))

        for (client, billed) in clients {
            switch await attempt(client, billed: billed, seconds: seconds, audioURL: audioURL, language: language, vocabulary: vocabulary) {
            case .text(let text):
                return .success((text, client.name, failures))
            case .failed(let failure):
                failures.append(failure)
            }
        }
        return .failure(.allEnginesFailed(failures.joined(separator: " · ")))
    }

    private enum RaceEvent {
        case preferred(Race.Attempt), fallback(Race.Attempt), deadline
    }

    /// The loser is not cancelled: it runs to its end in the background and `attempt` logs
    /// its time. Cancelling it hid the one number that says whether the deadline is right,
    /// Scribe's real time on the dictations it lost. The requests are unstructured tasks
    /// for that reason, since a task group would wait for the loser before returning.
    /// Both clients read the audio before their first suspension, so the pipeline may
    /// delete the file as soon as a text is chosen.
    private static func race(
        audioURL: URL,
        seconds: TimeInterval,
        language: String,
        vocabulary: [String]
    ) async -> (winner: (text: String, engine: String)?, failures: [String]) {
        let preferredClient = ElevenLabsClient()
        let fallbackClient = MicrosoftClient()
        let deadline = Race.deadline(forAudio: seconds)
        let stopwatch = Stopwatch()
        let (events, continuation) = AsyncStream.makeStream(of: RaceEvent.self)

        let preferred = Task {
            continuation.yield(.preferred(await attempt(preferredClient, billed: .elevenLabs, seconds: seconds, audioURL: audioURL, language: language, vocabulary: vocabulary)))
        }
        let fallback = Task {
            continuation.yield(.fallback(await attempt(fallbackClient, billed: .microsoft, seconds: seconds, audioURL: audioURL, language: language, vocabulary: vocabulary)))
        }
        let timer = Task {
            try? await Task.sleep(for: deadline)
            continuation.yield(.deadline)
        }
        defer {
            timer.cancel()
            continuation.finish()
        }

        // A cancelled dictation still cancels both requests: nobody is waiting for a text.
        return await withTaskCancellationHandler {
            var race = Race()
            for await event in events {
                switch event {
                case .preferred(let attempt): race.preferred = attempt
                case .fallback(let attempt): race.fallback = attempt
                case .deadline: race.deadlinePassed = true
                }
                let failures = [race.preferred, race.fallback].compactMap { attempt -> String? in
                    if case .failed(let failure) = attempt { return failure }
                    return nil
                }
                switch race.verdict {
                case .wait:
                    continue
                case .preferred:
                    Log.transcription.notice("course : \(preferredClient.name, privacy: .public) retenu en \(stopwatch.milliseconds) ms")
                    return ((race.preferred?.text ?? "", preferredClient.name), failures)
                case .fallback:
                    let why = race.preferred != nil ? "en échec"
                        : deadline == .zero ? "sans délai, audio de \(Int(seconds)) s"
                        : "hors délai"
                    Log.transcription.notice(
                        "course : \(fallbackClient.name, privacy: .public) retenu en \(stopwatch.milliseconds) ms, \(preferredClient.name, privacy: .public) \(why, privacy: .public)"
                    )
                    return ((race.fallback?.text ?? "", fallbackClient.name), failures)
                case .bothFailed:
                    return (nil, failures)
                }
            }
            return (nil, [])
        } onCancel: {
            preferred.cancel()
            fallback.cancel()
            continuation.finish()
        }
    }

    /// A cancelled request belongs to a dictation the user cancelled, not a failure, and
    /// is logged as such.
    private static func attempt(
        _ client: any TranscriptionClient,
        billed: Engine?,
        seconds: TimeInterval,
        audioURL: URL,
        language: String,
        vocabulary: [String]
    ) async -> Race.Attempt {
        let stopwatch = Stopwatch()
        do {
            let text = try await client.transcribe(audioURL: audioURL, language: language, vocabulary: vocabulary)
            // An answer is a billed request, even an empty one.
            if let billed {
                await UsageLedger.shared.charge(billed, seconds: seconds)
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                let failure = "\(client.name) : texte vide"
                Log.transcription.error("\(failure, privacy: .public)")
                return .failed(failure)
            }
            Log.transcription.notice(
                "\(client.name, privacy: .public) : \(trimmed.count) caractères en \(stopwatch.milliseconds) ms"
            )
            return .text(trimmed)
        } catch {
            if Task.isCancelled {
                Log.transcription.notice("\(client.name, privacy: .public) : abandonné après \(stopwatch.milliseconds) ms")
                return .failed("\(client.name) : abandonné")
            }
            let failure = describe(error, from: client)
            Log.transcription.error("\(failure, privacy: .public) (après \(stopwatch.milliseconds) ms)")
            return .failed(failure)
        }
    }

    /// `MagnetoError.api` already opens with the engine name, so prefixing it a second
    /// time produced "ElevenLabs Scribe v2 : ElevenLabs Scribe v2 : quota épuisé".
    private static func describe(_ error: Error, from client: any TranscriptionClient) -> String {
        if let magneto = error as? MagnetoError, case .api = magneto {
            return magneto.localizedDescription
        }
        return "\(client.name) : \(error.localizedDescription)"
    }
}
