import ActivityKit
import Foundation

struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable {
            case recording, transcribing, ready, failed
        }

        var phase: Phase
        var startedAt: Date
        var detail: String
    }
}

extension RecordingAttributes.ContentState.Phase {
    var symbol: String {
        switch self {
        case .recording: return "mic.fill"
        case .transcribing: return "hourglass"
        case .ready: return "doc.on.clipboard"
        case .failed: return "exclamationmark.triangle"
        }
    }

    /// Short on purpose: the expanded island wrapped "Enregistrement" onto two lines.
    var label: String {
        switch self {
        case .recording: return "Dictée"
        case .transcribing: return "Transcription"
        case .ready: return "Texte prêt"
        case .failed: return "Échec"
        }
    }
}
