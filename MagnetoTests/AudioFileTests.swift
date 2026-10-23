import AVFoundation
import Testing

/// The cloud engines receive the FLAC made from each recording, so the conversion has to
/// keep every sample: a file truncated or refused would fail every dictation at once.
@Suite("AudioFile")
struct AudioFileTests {
    @Test("a second of 16-bit WAV comes back as a second of 16-bit FLAC, a third of the size")
    func compressed() throws {
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("magneto-test-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        do {
            let file = try AVAudioFile(forWriting: wav, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000))
            buffer.frameLength = 16_000
            let samples = try #require(buffer.floatChannelData)[0]
            for i in 0..<16_000 {
                samples[i] = 0.3 * sin(Float(i) * 2 * .pi * 440 / 16_000)
            }
            try file.write(from: buffer)
        }

        let flac = try #require(AudioFile.compressed(wav))
        defer { try? FileManager.default.removeItem(at: flac) }
        let read = try AVAudioFile(forReading: flac)
        #expect(read.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatFLAC)
        #expect(read.length == 16_000)
        #expect(AudioFile.mimeType(of: flac) == "audio/flac")
        #expect(AudioFile.mimeType(of: wav) == "audio/wav")
        let sizes = try [wav, flac].map { try #require(FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) }
        #expect(sizes[1] * 2 < sizes[0])
    }

    @Test("a file that is not audio gives no FLAC, so the WAV is sent")
    func unreadable() throws {
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("magneto-test-\(UUID().uuidString).wav")
        try Data("pas de l'audio".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }
        #expect(AudioFile.compressed(junk) == nil)
        #expect(!FileManager.default.fileExists(atPath: junk.deletingPathExtension().appendingPathExtension("flac").path))
    }
}
