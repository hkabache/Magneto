import AVFoundation
import Foundation

/// The path the built-in microphone has always taken. `AVAudioRecorder` picks the system's
/// default input by itself and offers no way to know whether that input ever answered, but
/// on the built-in microphone it has never lost a sample, so it keeps that device. Every
/// other input goes to `ResilientCapture`, which survives what this one cannot.
@MainActor
final class SimpleCapture: Capture {
    private let recorder: AVAudioRecorder
    private let clock = Stopwatch()
    private var announced = false

    init(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw MagnetoError.micStartFailed
        }
    }

    func poll() -> CaptureState {
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let level = max(0, min(1, pow(10, db / 20) * 4))
        guard !announced else {
            return CaptureState(level: level, status: .live)
        }
        let elapsed = clock.milliseconds
        switch MicReadiness(averagePower: db, elapsedMilliseconds: elapsed) {
        case .waiting:
            return CaptureState(level: level, status: .warmingUp)
        case .delivering:
            announced = true
            Log.pipeline.notice("micro actif après \(elapsed) ms")
        case .assumed:
            announced = true
            Log.pipeline.notice("micro sans niveau après \(elapsed) ms, enregistrement annoncé quand même")
        }
        return CaptureState(level: level, status: .live)
    }

    func finish() {
        recorder.stop()
    }
}

/// `record()` returns true well before the hardware delivers a sample, so the interface
/// waits for a microphone that answers rather than one that was merely asked.
enum MicReadiness {
    case waiting, delivering, assumed

    /// An input that is not running yet reports the meter's floor value, where a running
    /// one always carries the room's noise, so the meter tells the two apart.
    private static let silenceFloor: Float = -120

    /// A meter stuck at the floor is not proof of a dead input: a muted or virtual device
    /// sends digital silence forever. Past this delay the wait costs more than it saves,
    /// so the recording is announced anyway.
    private static let assumeLiveAfterMilliseconds = 2_500

    init(averagePower: Float, elapsedMilliseconds: Int) {
        if averagePower > Self.silenceFloor {
            self = .delivering
        } else {
            self = elapsedMilliseconds >= Self.assumeLiveAfterMilliseconds ? .assumed : .waiting
        }
    }
}
