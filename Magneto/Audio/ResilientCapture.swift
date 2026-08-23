import AVFoundation
import CoreMedia
import Foundation

/// The path for every input that is not the built-in microphone, which in practice means a
/// Bluetooth headset. Two things go wrong there and neither raises an error: a stream
/// opened while the link is renegotiating never delivers a sample, and a renegotiation
/// mid-sentence stops one that was delivering. Both are survivable because this path owns
/// the file, so a rebuilt session carries on writing into it, one gap poorer instead of
/// lost. Nothing here runs on the main thread: opening an input takes long enough to be
/// felt, and a frozen interface is what made a slow start look like a broken app.
@MainActor
final class ResilientCapture: Capture {
    private let sink: AudioSink
    private let host: CaptureHost

    /// Time from the hotkey, which is what the person waiting on the pill experiences.
    private let dictation = Stopwatch()

    /// Time since the session confirmed it was running, which is what the health of the
    /// stream is judged on. Nil while the input is being opened.
    private var running: Stopwatch?

    private var status: Recorder.Status = .warmingUp
    private var rebuilds = 0
    private var opening = true
    private var finished = false

    /// Past this many rebuilds the input is not coming back, and rebuilding again only adds
    /// gaps to a recording that is already lost.
    private static let maximumRebuilds = 5

    /// The hardware needs a moment to settle before it can be asked again.
    private static let settleMilliseconds = 200

    init(url: URL) throws {
        let sink = try AudioSink(url: url)
        self.sink = sink
        host = CaptureHost(sink: sink)
        host.onTrouble = { [weak self] reason in
            self?.rebuild(because: reason)
        }
        host.open { [weak self] outcome in
            self?.opened(outcome)
        }
    }

    func poll() -> CaptureState {
        let state = sink.state()
        let elapsed = dictation.milliseconds
        if !finished, status != .unresponsive, let running {
            switch CaptureHealth(
                loudestSignal: state.loudestSignal,
                idleMilliseconds: state.idleMilliseconds,
                elapsedMilliseconds: running.milliseconds
            ) {
            case .starting:
                break
            case .live:
                if status != .live {
                    status = .live
                    Log.pipeline.notice("micro actif après \(elapsed) ms")
                }
            case .silent:
                rebuild(
                    because: state.buffers == 0
                        ? "aucun tampon après \(running.milliseconds) ms"
                        : "\(state.buffers) tampons de silence après \(running.milliseconds) ms"
                )
            case .stalled:
                rebuild(because: "flux interrompu depuis \(state.idleMilliseconds ?? 0) ms")
            }
        }
        return CaptureState(level: min(1, state.signal * 4), status: status)
    }

    /// The file is flushed here and not on the session's queue, because the caller reads the
    /// recording's duration as soon as this returns. A sample buffer delivered in the
    /// meantime finds a closed sink and writes nothing.
    func finish() {
        finished = true
        let dropped = sink.finish()
        host.teardown()
        if dropped > 0 {
            Log.pipeline.error("\(dropped) tampons perdus en cours d'écriture")
        }
    }

    private func opened(_ outcome: CaptureHost.Opening) {
        opening = false
        guard !finished else {
            host.teardown()
            return
        }
        switch outcome {
        case .started(let milliseconds):
            Log.pipeline.notice("session de capture démarrée en \(milliseconds) ms")
            running = Stopwatch()
        case .failed(let message):
            Log.pipeline.error("session de capture non démarrée : \(message, privacy: .public)")
            rebuild(because: "session non démarrée")
        }
    }

    private func rebuild(because reason: String) {
        guard !finished, !opening, status != .unresponsive else { return }
        guard rebuilds < Self.maximumRebuilds else {
            let spent = rebuilds
            status = .unresponsive
            Log.pipeline.error("micro injoignable après \(spent) relances")
            return
        }
        rebuilds += 1
        let attempt = rebuilds
        opening = true
        running = nil
        if status == .live {
            status = .recovering
        }
        Log.pipeline.error("relance \(attempt)/\(Self.maximumRebuilds) : \(reason, privacy: .public)")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.settleMilliseconds))
            guard let self, !self.finished else { return }
            self.host.open { [weak self] outcome in
                self?.opened(outcome)
            }
        }
    }
}

/// What the samples say about a stream that reports no error either way.
enum CaptureHealth {
    /// Nothing usable yet, and the link may still be switching.
    case starting
    /// Samples are arriving and they carry sound.
    case live
    /// The stream runs on paper but every sample is digital silence, which no microphone
    /// produces: the stream we hold is not the one the device ended up using.
    case silent
    /// Samples stopped arriving.
    case stalled

    /// A room's noise clears this by orders of magnitude, and digital silence never does.
    private static let silenceFloor: Float = 1e-6

    /// A cold Bluetooth link was measured between 550 and 700 ms before its first sample,
    /// so the doubt is given twice that much room before the stream is called dead.
    private static let graceMilliseconds = 1_500

    /// A running input hands over a buffer every few dozen milliseconds. Long enough that
    /// no plausible buffer size trips it, short enough to lose a word rather than a phrase.
    private static let stallMilliseconds = 800

    init(loudestSignal: Float, idleMilliseconds: Int?, elapsedMilliseconds: Int) {
        guard loudestSignal > Self.silenceFloor else {
            self = elapsedMilliseconds < Self.graceMilliseconds ? .starting : .silent
            return
        }
        if let idleMilliseconds, idleMilliseconds >= Self.stallMilliseconds {
            self = .stalled
        } else {
            self = .live
        }
    }
}

/// Owns the capture session and every call into it, on one queue for configuration and
/// another for the samples, as Apple's own capture samples do.
///
/// This replaced `AVAudioEngine`, which was measured on this machine at 3146 ms just to
/// hand over its input node. macOS publishes a pair of AirPods as two separate devices, a
/// one-channel microphone and a two-channel output, and an audio graph can only address a
/// single device, so the engine silently builds an aggregate of the two and that is what
/// costs the seconds. A capture session has no output side to reconcile: same machine, same
/// AirPods, first buffer in 246 ms.
private final class CaptureHost: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum Opening {
        case started(milliseconds: Int)
        case failed(message: String)
    }

    /// Called on the main actor when the session reports it can no longer capture.
    var onTrouble: (@MainActor (String) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.hkabache.magneto.capture.session")
    private let sampleQueue = DispatchQueue(label: "com.hkabache.magneto.capture.samples", qos: .userInitiated)
    private let sink: AudioSink
    private var input: AVCaptureDeviceInput?
    private var observers: [NSObjectProtocol] = []

    init(sink: AudioSink) {
        self.sink = sink
        super.init()
        // Asking the capture stack for the file's own format leaves the sink nothing to
        // convert. It stays able to, because a device is free to answer with its own.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        observers = [
            NotificationCenter.default.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                self?.report("erreur de session : \(error?.localizedDescription ?? "cause inconnue")")
            },
            NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: nil,
                queue: nil
            ) { [weak self] note in
                guard let self, let gone = note.object as? AVCaptureDevice,
                      gone.uniqueID == self.input?.device.uniqueID else { return }
                self.report("périphérique déconnecté")
            },
        ]
    }

    func open(_ completion: @escaping @MainActor (Opening) -> Void) {
        sessionQueue.async { [self] in
            let stopwatch = Stopwatch()
            detach()
            // A rebuilt session is judged on its own samples, not on what the dead one left.
            sink.expectFreshStream()
            let problem = attach()
            let elapsed = stopwatch.milliseconds
            Task { @MainActor in
                completion(problem.map { Opening.failed(message: $0) } ?? .started(milliseconds: elapsed))
            }
        }
    }

    func teardown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        onTrouble = nil
        sessionQueue.async { [self] in
            detach()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = Self.buffer(from: sampleBuffer) else { return }
        sink.write(buffer)
    }

    /// Returns what went wrong, or nil when the session is running.
    private func attach() -> String? {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            return "aucun périphérique d'entrée"
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            return error.localizedDescription
        }
        // The configuration is committed whatever happens: a session left mid-configuration
        // is a session that never works again.
        session.beginConfiguration()
        var problem: String?
        if session.canAddInput(input) {
            session.addInput(input)
            self.input = input
        } else {
            problem = "entrée refusée par la session"
        }
        if problem == nil, !session.outputs.contains(output) {
            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                problem = "sortie refusée par la session"
            }
        }
        session.commitConfiguration()
        if let problem {
            return problem
        }
        session.startRunning()
        return session.isRunning ? nil : "la session n'a pas démarré"
    }

    private func detach() {
        if session.isRunning {
            session.stopRunning()
        }
        if let input {
            session.beginConfiguration()
            session.removeInput(input)
            session.commitConfiguration()
            self.input = nil
        }
    }

    private func report(_ reason: String) {
        guard let onTrouble else { return }
        Task { @MainActor in
            onTrouble(reason)
        }
    }

    private static func buffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: streamDescription) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}

/// Everything the audio thread touches, behind one lock, because the framework may call a
/// tap block on any thread. The main actor only ever reads a snapshot of it.
private final class AudioSink {
    struct State {
        let signal: Float
        let loudestSignal: Float
        let idleMilliseconds: Int?
        let buffers: Int
    }

    private let lock = NSLock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var signal: Float = 0
    private var loudest: Float = 0
    private var sinceLastBuffer: Stopwatch?
    private var buffers = 0
    private var dropped = 0

    init(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return }
        let strength = Self.rms(of: buffer)
        signal = strength
        loudest = max(loudest, strength)
        sinceLastBuffer = Stopwatch()
        buffers += 1
        guard let converted = convert(buffer, to: file.processingFormat) else {
            dropped += 1
            return
        }
        do {
            try file.write(from: converted)
        } catch {
            dropped += 1
        }
    }

    func state() -> State {
        lock.lock()
        defer { lock.unlock() }
        return State(
            signal: signal,
            loudestSignal: loudest,
            idleMilliseconds: sinceLastBuffer?.milliseconds,
            buffers: buffers
        )
    }

    func expectFreshStream() {
        lock.lock()
        defer { lock.unlock() }
        signal = 0
        loudest = 0
        sinceLastBuffer = nil
        buffers = 0
    }

    /// Releasing the file is what flushes it and completes the WAV header.
    func finish() -> Int {
        lock.lock()
        defer { lock.unlock() }
        file = nil
        converter = nil
        sourceFormat = nil
        return dropped
    }

    /// The hardware format is whatever the device imposes, and a rebuilt graph can come
    /// back with another one, so the converter follows the buffers rather than a format
    /// settled once at the start.
    private func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            sourceFormat = buffer.format
        }
        guard let converter else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var failure: NSError?
        let outcome = converter.convert(to: output, error: &failure) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard outcome != .error, failure == nil, output.frameLength > 0 else { return nil }
        return output
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var total: Float = 0
        for index in 0..<frames {
            let sample = channel[index]
            total += sample * sample
        }
        return (total / Float(frames)).squareRoot()
    }
}
