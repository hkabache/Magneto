import AVFoundation
import Foundation

enum AudioFile {
    /// From the file, not from the recorder: a recorder that stopped on its own reports
    /// zero, and the audio would be silently dropped.
    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return 0 }
        return Double(file.length) / rate
    }
}
