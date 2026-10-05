import ActivityKit
import AVFoundation
import Foundation

/// The iPhone pipeline, driven by the intent and nothing else: no window and no hotkey. It
/// runs in the app process the system launches in the background, and the Live Activity
/// is its only face. Every rule in here was measured on the phone before it landed.
@MainActor
final class Dictation: ObservableObject {
    static let shared = Dictation()

    enum Phase {
        case idle, recording, finishing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var startedAt = Date()
    @Published private(set) var lastError: String?
    @Published private(set) var history: [String]

    private var recorder: AVAudioRecorder?
    private var activity: Activity<RecordingAttributes>?
    private var watchdog: Task<Void, Never>?
    /// A dictation the watchdog closed: transcribed, and waiting for the next press to
    /// hand its text to the shortcut, since nothing else can carry it.
    private var pending: String?

    private let settings = AppSettings.shared

    private init() {
        history = UserDefaults.standard.stringArray(forKey: "history") ?? []
    }

    /// The text of the dictation this press ended, nil when it started one.
    func toggle() async -> String? {
        if let pending {
            self.pending = nil
            Log.pipeline.notice("texte en attente rendu au raccourci")
            return pending
        }
        switch phase {
        case .idle:
            await start()
            return nil
        case .recording:
            return await stop()
        case .finishing:
            return nil
        }
    }

    private func start() async {
        await endOrphans()
        startedAt = Date()
        lastError = nil
        do {
            activity = try Activity.request(attributes: RecordingAttributes(), content: content(.recording))
        } catch {
            // Not a stop: the system is documented to cut a recording that has no Live
            // Activity, and the failure that would follow says more than a refusal here.
            Log.pipeline.error("Live Activity refusée : \(error.localizedDescription, privacy: .public)")
        }
        // Checked after the activity exists: it is the only place this message can show.
        guard AVAudioApplication.shared.recordPermission == .granted else {
            await abort("Micro non autorisé. Ouvrez Magneto pour l'autoriser.")
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            // Mixable on purpose. A plain .record session is refused from the background
            // with cannotInterruptOthers: only the Now Playing app may silence the others
            // from there, and a mixable session silences nobody. .mixWithOthers is only
            // accepted with .playAndRecord, hence the category.
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetoothHFP])
            try await activate(session)
        } catch {
            await abort("Session audio refusée : \(describe(error))")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("magneto-\(UUID().uuidString).wav")
        do {
            let recorder = try AVAudioRecorder(url: url, settings: Self.wav16kMono)
            guard recorder.record() else {
                throw MagnetoError.micStartFailed
            }
            self.recorder = recorder
        } catch {
            // record() says false and nothing else, so the session is described instead:
            // the failures seemed to follow music, and only this line can confirm it.
            Log.pipeline.error("micro refusé, \(self.audioContext(session), privacy: .public)")
            // The recorder writes the file's header on creation, and only stop() removes it.
            try? FileManager.default.removeItem(at: url)
            deactivate()
            await abort(error.localizedDescription)
            return
        }
        phase = .recording
        // The same description on success, or a failure would have nothing to differ from.
        Log.pipeline.notice("dictée démarrée, \(self.audioContext(session), privacy: .public)")
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(900))
            guard !Task.isCancelled, let self, self.phase == .recording else { return }
            Log.pipeline.notice("dictée fermée par le garde-fou après 15 min")
            self.pending = await self.stop(closedByWatchdog: true)
        }
    }

    private func stop(closedByWatchdog: Bool = false) async -> String? {
        watchdog?.cancel()
        watchdog = nil
        guard let recorder else { return nil }
        phase = .finishing
        recorder.stop()
        self.recorder = nil
        let url = recorder.url
        defer { try? FileManager.default.removeItem(at: url) }

        let duration = AudioFile.duration(of: url)
        guard duration >= 0.5 else {
            Log.pipeline.notice("audio ignoré : \(duration, format: .fixed(precision: 2)) s")
            deactivate()
            await end(.failed, detail: "Rien entendu")
            return nil
        }
        Log.pipeline.notice("dictée : \(duration, format: .fixed(precision: 1)) s d'audio")
        await activity?.update(content(.transcribing))

        // The session stays active through the transcription: it is what keeps the process
        // alive between the last sample and the result.
        let result = await TranscriptionService.transcribe(
            audioURL: url,
            language: settings.language,
            vocabulary: settings.vocabulary,
            choice: settings.engineChoice
        )
        deactivate()

        switch result {
        case .failure(let error):
            await abort(error.localizedDescription)
            return nil
        case .success(let transcription):
            // A fallback is not an error, but staying silent about it let the quality
            // drop for days without a sign.
            if !transcription.failures.isEmpty {
                lastError = "\(transcription.failures.joined(separator: " · ")). Texte transcrit par \(transcription.engine)."
            }
            let ruled = settings.straightQuotes ? QuotePass.clean(transcription.text) : transcription.text
            guard !ruled.isEmpty else {
                await abort("La transcription est vide.")
                return nil
            }
            if settings.dictationJournal {
                DictationJournal.record(
                    audio: url,
                    raw: transcription.text,
                    ruled: ruled,
                    engine: transcription.engine
                )
            }
            pushHistory(ruled)
            Log.pipeline.notice("texte rendu : \(ruled.count) caractères")
            await end(.ready, detail: closedByWatchdog ? "15 min atteintes, appuyez pour copier" : transcription.engine)
            return ruled
        }
    }

    /// One retry, because a freshly launched process was refused once with '!pla',
    /// cannotStartPlaying, and accepted two seconds later with nothing changed.
    private func activate(_ session: AVAudioSession) async throws {
        do {
            try session.setActive(true)
        } catch {
            Log.pipeline.error("session audio refusée au premier essai : \(self.describe(error), privacy: .public)")
            try await Task.sleep(for: .milliseconds(300))
            try session.setActive(true)
        }
    }

    /// What the session looked like when the recorder was asked to start. Carries no
    /// dictated text, so it belongs in the system journal.
    private func audioContext(_ session: AVAudioSession) -> String {
        let inputs = session.currentRoute.inputs.map(\.portName).joined(separator: ", ")
        return "entrée \(inputs.isEmpty ? "aucune" : inputs)"
            + ", autre son \(session.isOtherAudioPlaying ? "en cours" : "absent")"
            + ", son secondaire à couper \(session.secondaryAudioShouldBeSilencedHint ? "oui" : "non")"
            + ", micro \(session.isInputAvailable ? "disponible" : "indisponible")"
            + ", \(Int(session.sampleRate)) Hz"
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func end(_ finalPhase: RecordingAttributes.ContentState.Phase, detail: String) async {
        phase = .idle
        guard let activity else { return }
        await activity.end(
            content(finalPhase, detail: detail),
            dismissalPolicy: .after(Date().addingTimeInterval(5))
        )
        self.activity = nil
    }

    /// A Live Activity still running with no recorder behind it means the process was
    /// killed mid-dictation. Ended activities stay listed until their dismissal date, so
    /// only the live ones count.
    private func endOrphans() async {
        let orphans = Activity<RecordingAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        guard !orphans.isEmpty else { return }
        Log.pipeline.error("\(orphans.count) Live Activity orpheline(s) : processus tué pendant une dictée")
        for orphan in orphans {
            await orphan.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends the dictation on an error the pill has to carry: there is no window to show it.
    private func abort(_ message: String) async {
        Log.pipeline.error("\(message, privacy: .public)")
        lastError = message
        await end(.failed, detail: message)
    }

    private func content(_ statePhase: RecordingAttributes.ContentState.Phase, detail: String = "") -> ActivityContent<RecordingAttributes.ContentState> {
        ActivityContent(
            state: RecordingAttributes.ContentState(phase: statePhase, startedAt: startedAt, detail: detail),
            staleDate: nil
        )
    }

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
    }

    private func pushHistory(_ text: String) {
        history.insert(text, at: 0)
        if history.count > 10 {
            history.removeLast(history.count - 10)
        }
        UserDefaults.standard.set(history, forKey: "history")
    }

    private static let wav16kMono: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]
}

extension Dictation.Phase {
    var symbol: String {
        switch self {
        case .idle: return "mic"
        case .recording: return "record.circle"
        case .finishing: return "hourglass"
        }
    }

    var statusLabel: String {
        switch self {
        case .idle: return "Prête à dicter"
        case .recording: return "Dictée en cours"
        case .finishing: return "Transcription…"
        }
    }
}
