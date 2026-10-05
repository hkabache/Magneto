import Foundation

/// MAI-Transcribe-2, served by Azure Speech's fast transcription endpoint behind the
/// `enhancedMode` flag. Public preview as of October 2026.
struct MicrosoftClient: TranscriptionClient {
    let name = "Microsoft MAI-Transcribe-2"

    /// The only regions serving MAI-Transcribe. An Azure key belongs to one region and
    /// is refused everywhere else, so the key check finds it among these rather than
    /// asking for it in a second field. France Central, though closer, was tried and
    /// answers "Enhanced mode with model is currently not supported yet".
    static let regions = ["northeurope", "eastus", "westus", "westus2", "centralindia", "southeastasia"]

    private static let regionDefault = "microsoftRegion"

    static var region: String? {
        get { UserDefaults.standard.string(forKey: regionDefault) }
        set { UserDefaults.standard.set(newValue, forKey: regionDefault) }
    }

    private struct Response: Decodable {
        struct Phrase: Decodable {
            let text: String
        }
        let combinedPhrases: [Phrase]
    }

    func transcribe(audioURL: URL, language: String, vocabulary: [String]) async throws -> String {
        guard let key = Keychain.get(Keychain.microsoft) else {
            throw MagnetoError.missingKey("Microsoft")
        }
        guard let region = Self.region else {
            throw MagnetoError.api(engine: name, message: "région inconnue, recollez la clé")
        }
        let definition = try Self.definition(language: language, vocabulary: vocabulary)
        let request = try Self.request(key: key, region: region, definition: definition, audio: Data(contentsOf: audioURL))

        let (data, http) = try await HTTP.send(request.0, body: request.1)
        guard http.statusCode == 200 else {
            throw MagnetoError.api(engine: name, message: Self.reason(status: http.statusCode, body: data))
        }
        return try JSONDecoder().decode(Response.self, from: data).combinedPhrases
            .map(\.text)
            .joined(separator: " ")
    }

    /// `clean` is the counterpart of Scribe's `no_verbatim`, and the language is forced
    /// for the same reason it is there: the app dictates in one language.
    static func definition(language: String, vocabulary: [String]) throws -> String {
        struct Definition: Encodable {
            struct EnhancedMode: Encodable {
                struct Options: Encodable {
                    let transcribeStyle = "clean"
                    let timestamps = "none"
                }
                let enabled = true
                let model = "MAI-Transcribe-2"
                let modelOptions = Options()
            }
            struct PhraseList: Encodable {
                let phrases: [String]
            }
            let locales: [String]
            let enhancedMode = EnhancedMode()
            let phraseList: PhraseList?
        }
        let phrases = Array(vocabulary.prefix(100))
        let value = Definition(locales: [language], phraseList: phrases.isEmpty ? nil : .init(phrases: phrases))
        guard let json = String(data: try JSONEncoder().encode(value), encoding: .utf8) else {
            throw MagnetoError.api(engine: "Microsoft MAI-Transcribe-2", message: "requête illisible")
        }
        return json
    }

    static func request(key: String, region: String, definition: String, audio: Data) throws -> (URLRequest, Data) {
        guard let url = URL(
            string: "https://\(region).api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15"
        ) else {
            throw MagnetoError.api(engine: "Microsoft MAI-Transcribe-2", message: "URL invalide")
        }
        var form = Multipart()
        form.addField("definition", definition)
        form.addFile("audio", filename: "audio.wav", mime: "audio/wav", data: audio)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        return (request, form.finalized())
    }

    private static func reason(status: Int, body: Data) -> String {
        switch status {
        case 401, 403: return "clé refusée"
        case 429: return "quota atteint"
        default: return "HTTP \(status) \(HTTP.errorBody(body))"
        }
    }
}
