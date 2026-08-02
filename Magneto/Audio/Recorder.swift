import AVFoundation
import Foundation

@MainActor
final class Recorder: ObservableObject {
    @Published private(set) var level: Float = 0

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private(set) var currentURL: URL?

    var duration: TimeInterval {
        recorder?.currentTime ?? 0
    }

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("magneto-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw MagnetoError.micStartFailed
        }
        self.recorder = recorder
        currentURL = url
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLevel()
            }
        }
    }

    func stop() -> URL? {
        levelTimer?.invalidate()
        levelTimer = nil
        level = 0
        recorder?.stop()
        recorder = nil
        let url = currentURL
        currentURL = nil
        return url
    }

    func cancel() {
        if let url = stop() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func updateLevel() {
        guard let recorder else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let linear = pow(10, db / 20)
        level = max(0, min(1, linear * 4))
    }
}
