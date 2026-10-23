import Foundation

/// Voxtral Small Transcribe 3, public preview as of October 2026. Chosen over Mini on
/// 83 dictations replayed from the journal: the two texts differed by 3 % of their words,
/// each one right where the other erred, and Mini's 150 ms lead at the median vanishes
/// in the race, where the fallback waits out Scribe's deadline anyway.
struct MistralClient: TranscriptionClient {
    let name = "Mistral Voxtral Small 3"

    static let model = "voxtral-small-transcribe-3"

    private struct Response: Decodable {
        let text: String
    }

    func transcribe(audioURL: URL, language: String, vocabulary: [String]) async throws -> String {
        guard let key = Keychain.get(Keychain.mistral) else {
            throw MagnetoError.missingKey("Mistral")
        }

        var form = Multipart()
        form.addField("model", Self.model)
        form.addField("language", language)
        for term in Self.contextBias(from: vocabulary) {
            form.addField("context_bias", term)
        }
        form.addFile("file", filename: "audio.\(audioURL.pathExtension)", mime: AudioFile.mimeType(of: audioURL), data: try Data(contentsOf: audioURL))

        guard let url = URL(string: "https://api.mistral.ai/v1/audio/transcriptions") else {
            throw MagnetoError.api(engine: name, message: "URL invalide")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90

        let (data, http) = try await HTTP.send(request, body: form.finalized())
        guard http.statusCode == 200 else {
            throw MagnetoError.api(engine: name, message: Self.reason(status: http.statusCode, body: data))
        }
        return try JSONDecoder().decode(Response.self, from: data).text
    }

    private static func reason(status: Int, body: Data) -> String {
        switch status {
        case 401: return "clé refusée"
        case 429: return "quota atteint"
        default: return "HTTP \(status) \(HTTP.errorBody(body))"
        }
    }

    /// The entries share the model's 32k context with the audio, and a request over it
    /// fails rather than being cut, so the list stays short. Punctuation is accepted.
    static func contextBias(from vocabulary: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for word in vocabulary {
            let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(cleaned.lowercased()).inserted else { continue }
            result.append(cleaned)
            if result.count == 100 { break }
        }
        return result
    }
}
