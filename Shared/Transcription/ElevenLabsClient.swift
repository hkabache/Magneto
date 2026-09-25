import Foundation

struct ElevenLabsClient: TranscriptionClient {
    let name = "ElevenLabs Scribe v2"

    private struct Response: Decodable {
        let text: String
    }

    func transcribe(audioURL: URL, language: String, vocabulary: [String]) async throws -> String {
        guard let key = Keychain.get(Keychain.elevenLabs) else {
            throw MagnetoError.missingKey("ElevenLabs")
        }

        var form = Multipart()
        form.addField("model_id", "scribe_v2")
        form.addField("language_code", language)
        form.addField("tag_audio_events", "false")
        form.addField("timestamps_granularity", "none")
        form.addField("no_verbatim", "true")
        for term in Self.keyterms(from: vocabulary) {
            form.addField("keyterms", term)
        }
        form.addFile("file", filename: "audio.wav", mime: "audio/wav", data: try Data(contentsOf: audioURL))

        guard let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text") else {
            throw MagnetoError.api(engine: name, message: "URL invalide")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90

        let (data, http) = try await HTTP.send(request, body: form.finalized())
        guard http.statusCode == 200 else {
            throw MagnetoError.api(engine: name, message: Self.reason(status: http.statusCode, body: data))
        }
        return try JSONDecoder().decode(Response.self, from: data).text
    }

    /// An exhausted quota comes back as a plain 401, the same as a bad key, and only
    /// the body separates them. Both deserve a sentence rather than a status code,
    /// since this text is what the user reads when a dictation falls back.
    private static func reason(status: Int, body: Data) -> String {
        struct Payload: Decodable {
            struct Detail: Decodable {
                let status: String?
            }
            let detail: Detail?
        }
        switch (try? JSONDecoder().decode(Payload.self, from: body))?.detail?.status {
        case "quota_exceeded":
            return "quota épuisé"
        case "invalid_api_key":
            return "clé refusée"
        default:
            return "HTTP \(status) \(HTTP.errorBody(body))"
        }
    }

    /// Scribe v2 rejects `<>{}[]\`, terms over 50 chars or over 5 words; >100 keyterms
    /// triggers a 20s minimum billing so the list is capped there.
    static func keyterms(from vocabulary: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for word in vocabulary {
            let cleaned = word
                .filter { !"<>{}[]\\".contains($0) }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty,
                  cleaned.count < 50,
                  cleaned.split(separator: " ").count <= 5,
                  seen.insert(cleaned.lowercased()).inserted
            else { continue }
            result.append(cleaned)
            if result.count == 100 { break }
        }
        return result
    }
}
