import AVFoundation
import Foundation
import Speech

struct AppleSpeechClient: TranscriptionClient {
    let name = "Apple (local)"

    func transcribe(audioURL: URL, language: String, vocabulary: [String]) async throws -> String {
        let locale = Locale(identifier: language == "fr" ? "fr_FR" : "en_US")
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            throw MagnetoError.unsupportedLocale(locale.identifier)
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let collected = collect(transcriber)

        let file = try AVAudioFile(forReading: audioURL)
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        return try await collected
    }

    private func collect(_ transcriber: SpeechTranscriber) async throws -> String {
        var parts: [String] = []
        for try await result in transcriber.results {
            parts.append(String(result.text.characters))
        }
        return parts.joined()
    }
}
