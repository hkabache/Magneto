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

enum TranscriptionService {
    /// Failures are reported alongside a success, not only when everything fails: a
    /// primary engine that dies and leaves a lesser one to answer used to be entirely
    /// invisible, so the quality dropped without a word.
    static func transcribe(
        audioURL: URL,
        language: String,
        vocabulary: [String]
    ) async -> Result<(text: String, engine: String, failures: [String]), MagnetoError> {
        var clients: [any TranscriptionClient] = []
        if Keychain.exists(Keychain.elevenLabs) {
            clients.append(ElevenLabsClient())
        }
        if Keychain.exists(Keychain.mistral) {
            clients.append(VoxtralClient())
        }
        clients.append(AppleSpeechClient())

        var failures: [String] = []
        for client in clients {
            do {
                let text = try await client.transcribe(audioURL: audioURL, language: language, vocabulary: vocabulary)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    failures.append("\(client.name) : texte vide")
                    continue
                }
                return .success((trimmed, client.name, failures))
            } catch {
                failures.append(describe(error, from: client))
            }
        }
        return .failure(.allEnginesFailed(failures.joined(separator: " · ")))
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
