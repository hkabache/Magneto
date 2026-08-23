import AVFoundation
import Foundation

/// What a dictation polls its capture for, whichever path it took.
@MainActor
protocol Capture: AnyObject {
    func poll() -> CaptureState
    func finish()
}

struct CaptureState {
    let level: Float
    let status: Recorder.Status
}

/// Picks a capture path at the start of each dictation and publishes what it reports. The
/// fork exists because the built-in microphone has never failed on `AVAudioRecorder`, while
/// a Bluetooth link needs a graph that can be rebuilt mid-sentence. Once the resilient path
/// has proven itself on headphones, it can take over the built-in microphone too and this
/// fork goes away.
@MainActor
final class Recorder: ObservableObject {
    /// What the pill is allowed to claim. An input that was asked to record is not yet one
    /// that answered, and one that answered can stop answering.
    enum Status {
        case warmingUp, live, recovering, unresponsive
    }

    @Published private(set) var level: Float = 0
    @Published private(set) var status: Status = .warmingUp

    private var capture: Capture?
    private var ticker: Timer?
    private(set) var currentURL: URL?

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("magneto-\(UUID().uuidString).wav")
        let device = InputDevice.current
        // Logged before the capture exists rather than after: opening a Bluetooth input
        // takes seconds, and the journal has to show where those seconds went.
        Log.pipeline.notice(
            "entrée \(device.transport, privacy: .public) : capture \(device.isBuiltIn ? "simple" : "résiliente", privacy: .public)"
        )
        let capture: Capture
        do {
            if device.isBuiltIn {
                capture = try SimpleCapture(url: url)
            } else {
                capture = try ResilientCapture(url: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        self.capture = capture
        currentURL = url
        level = 0
        status = .warmingUp
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() -> URL? {
        ticker?.invalidate()
        ticker = nil
        capture?.finish()
        capture = nil
        level = 0
        status = .warmingUp
        let url = currentURL
        currentURL = nil
        return url
    }

    func cancel() {
        if let url = stop() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func tick() {
        guard let capture else { return }
        let state = capture.poll()
        level = state.level
        if status != state.status {
            status = state.status
        }
    }
}
