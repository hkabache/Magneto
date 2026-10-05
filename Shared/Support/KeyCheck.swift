import Foundation

/// A pasted key looks the same whether it works or not, and the only other feedback is
/// a dictation that quietly falls back to a lesser engine. Each key is therefore probed
/// as soon as it is stored.
///
/// The question asked is deliberately narrow: does the provider accept this key. A
/// server error or a rate limit says nothing about the key itself, so only an explicit
/// refusal counts as a failure.
enum KeyCheck {
    enum Outcome {
        case valid
        /// Accepted, but unable to serve right now. A quota is not a bad key, and
        /// telling someone to check a key that is perfectly fine sends them nowhere.
        case unusable(String)
        case refused(String)
    }

    static func run(account: String, key: String) async -> Outcome {
        if account == Keychain.microsoft {
            return await microsoft(key: key)
        }
        guard let request = request(account: account, key: key) else {
            return .valid
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .refused("Réponse illisible de \(provider(account))")
            }
            if http.statusCode == 429 {
                return .unusable("Quota \(provider(account)) atteint")
            }
            guard http.statusCode == 401 || http.statusCode == 403 else {
                return .valid
            }
            // ElevenLabs answers an exhausted quota with the same 401 as a bad key,
            // and only the body tells them apart.
            if account == Keychain.elevenLabs, quotaExceeded(data) {
                return .unusable("Quota ElevenLabs épuisé. La clé est valide")
            }
            return .refused("Clé refusée par \(provider(account))")
        } catch {
            return .refused("Vérification impossible, réseau indisponible")
        }
    }

    private static func quotaExceeded(_ data: Data) -> Bool {
        struct Body: Decodable {
            struct Detail: Decodable {
                let status: String?
            }
            let detail: Detail?
        }
        return (try? JSONDecoder().decode(Body.self, from: data))?.detail?.status == "quota_exceeded"
    }

    /// Where the key of an account is created, opened from the key field on both apps.
    static func keysPage(for account: String) -> URL? {
        switch account {
        case Keychain.elevenLabs: return URL(string: "https://elevenlabs.io/app/api/api-keys")
        case Keychain.microsoft: return URL(string: "https://portal.azure.com/#create/Microsoft.CognitiveServicesSpeechServices")
        default: return nil
        }
    }

    private static func provider(_ account: String) -> String {
        switch account {
        case Keychain.elevenLabs: return "ElevenLabs"
        case Keychain.microsoft: return "Microsoft"
        default: return account
        }
    }

    private static func request(account: String, key: String) -> URLRequest? {
        switch account {
        case Keychain.elevenLabs:
            return elevenLabsProbe(key: key)
        default:
            return nil
        }
    }

    /// ElevenLabs keys carry per-endpoint permissions, so a key scoped to transcription
    /// alone is refused by every read endpoint and would look broken. The only endpoint
    /// it can answer for is transcription itself, which validates the form before
    /// authenticating: an incomplete request returns 422 whatever the key is worth.
    ///
    /// The request is therefore complete but carries bytes that are not audio. The key
    /// is authenticated, then the audio is rejected, so nothing is transcribed and
    /// nothing is billed.
    private static func elevenLabsProbe(key: String) -> URLRequest? {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text") else { return nil }
        var form = Multipart()
        form.addField("model_id", "scribe_v2")
        form.addFile("file", filename: "probe.wav", mime: "audio/wav", data: Data("probe".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()
        return request
    }

    /// An Azure key is refused outside its own region, so the probe goes to every region
    /// serving MAI-Transcribe at once, and the one that accepts is kept for dictation.
    /// The audio part is not audio: the key is authenticated, the body rejected, and
    /// nothing is billed.
    private static func microsoft(key: String) async -> Outcome {
        let statuses = await withTaskGroup(of: (String, Int?).self) { group in
            for region in MicrosoftClient.regions {
                group.addTask {
                    guard let definition = try? MicrosoftClient.definition(language: "fr", vocabulary: []),
                          let probe = try? MicrosoftClient.request(
                              key: key, region: region, definition: definition, audio: Data("probe".utf8)
                          )
                    else { return (region, nil) }
                    var request = probe.0
                    request.timeoutInterval = 15
                    let response = try? await URLSession.shared.upload(for: request, from: probe.1)
                    return (region, (response?.1 as? HTTPURLResponse)?.statusCode)
                }
            }
            var result: [(String, Int?)] = []
            for await status in group {
                result.append(status)
            }
            return result
        }
        guard let accepted = statuses.first(where: { $0.1.map { $0 != 401 && $0 != 403 } ?? false }) else {
            if statuses.allSatisfy({ $0.1 == nil }) {
                return .refused("Vérification impossible, réseau indisponible")
            }
            MicrosoftClient.region = nil
            // An Azure key works in its own region only, so a refusal everywhere almost
            // always means a resource created in a region that does not serve the model.
            return .refused("Clé refusée. MAI-Transcribe-2 n'est servi qu'en North Europe, East US, West US, West US 2, Central India et Southeast Asia : une ressource créée ailleurs ne marche pas")
        }
        MicrosoftClient.region = accepted.0
        Log.transcription.notice("clé Microsoft acceptée en \(accepted.0, privacy: .public)")
        if accepted.1 == 429 {
            return .unusable("Quota Microsoft atteint")
        }
        return .valid
    }
}
