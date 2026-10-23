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

    /// The recording as FLAC, for the cloud engines. It carries the same 16-bit samples as
    /// the WAV in about a third of the bytes, and the bytes were the delay: 48 dictations
    /// replayed through Scribe came back in 1.15 s at the median instead of 1.52 s, 0.7 s
    /// sooner between 30 and 45 s of audio, with no more change in the text than two sends
    /// of the same WAV show. Voxtral answers it as fast as the WAV.
    ///
    /// Converted after the recording rather than recorded as FLAC: `AVAudioRecorder` writes
    /// FLAC from the microphone's full depth, whose noisy low bits shrank a dictation by a
    /// fifth instead of two thirds. Reading as 16-bit integers keeps the WAV's own samples.
    /// Nil when the conversion fails, and the WAV is sent as before.
    static func compressed(_ wav: URL) -> URL? {
        let flac = wav.deletingPathExtension().appendingPathExtension("flac")
        let stopwatch = Stopwatch()
        do {
            let input = try AVAudioFile(forReading: wav, commonFormat: .pcmFormatInt16, interleaved: true)
            let output = try AVAudioFile(
                forWriting: flac,
                settings: [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: input.fileFormat.sampleRate, AVNumberOfChannelsKey: 1],
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
            guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 16_000) else {
                return nil
            }
            while input.framePosition < input.length {
                try input.read(into: buffer)
                try output.write(from: buffer)
            }
        } catch {
            Log.transcription.error("FLAC impossible, envoi en WAV : \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: flac)
            return nil
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: flac.path)[.size] as? Int) ?? 0
        Log.transcription.notice("FLAC : \(size / 1024) Ko en \(stopwatch.milliseconds) ms")
        return flac
    }

    static func mimeType(of url: URL) -> String {
        url.pathExtension == "flac" ? "audio/flac" : "audio/wav"
    }
}
