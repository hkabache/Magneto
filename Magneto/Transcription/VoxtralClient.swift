import Foundation

struct VoxtralClient: TranscriptionClient {
    let name = "Voxtral"

    private struct Response: Decodable {
        let text: String
    }

    func transcribe(audioURL: URL, language: String, vocabulary: [String]) async throws -> String {
        guard let key = Keychain.get(Keychain.mistral) else {
            throw MagnetoError.missingKey("Mistral")
        }

        var form = Multipart()
        form.addField("model", "voxtral-mini-2602")
        form.addField("language", language)
        for token in Self.contextBias(from: vocabulary) {
            form.addField("context_bias", token)
        }
        form.addFile("file", filename: "audio.wav", mime: "audio/wav", data: try Data(contentsOf: audioURL))

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
            throw MagnetoError.api(engine: name, message: "HTTP \(http.statusCode) \(HTTP.errorBody(data))")
        }
        return try JSONDecoder().decode(Response.self, from: data).text
    }

    /// Voxtral only accepts single words: multi-word terms are split, tokens trimmed
    /// of surrounding punctuation, capped at 100.
    static func contextBias(from vocabulary: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for word in vocabulary {
            for token in word.split(whereSeparator: \.isWhitespace) {
                let cleaned = String(token).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                guard !cleaned.isEmpty, seen.insert(cleaned.lowercased()).inserted else { continue }
                result.append(cleaned)
                if result.count == 100 { return result }
            }
        }
        return result
    }
}
