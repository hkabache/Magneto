import Foundation

enum MagnetoError: LocalizedError {
    case missingKey(String)
    case micStartFailed
    case api(engine: String, message: String)
    case emptyTranscript
    case unsupportedLocale(String)
    case allEnginesFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider):
            return "Clé API manquante pour \(provider)."
        case .micStartFailed:
            return "Impossible de démarrer l'enregistrement micro."
        case .api(let engine, let message):
            return "\(engine) : \(message)"
        case .emptyTranscript:
            return "La transcription est vide."
        case .unsupportedLocale(let locale):
            return "Langue non supportée par le moteur local (\(locale))."
        case .allEnginesFailed(let details):
            return "Aucun moteur de transcription n'a abouti. \(details)"
        case .timeout:
            return "Délai dépassé."
        }
    }
}
