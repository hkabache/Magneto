import AVFoundation
import AppKit
import Foundation
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Phase {
        case idle, recording, transcribing
    }

    static let shared = AppState()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var busyLabel = "Transcription…"
    @Published var lastError: String?
    @Published private(set) var history: [String]
    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted

    let settings = AppSettings.shared
    let recorder = Recorder()
    private lazy var overlay = OverlayController(app: self)

    private var lastToggle = Date.distantPast
    private var pendingStart: Task<Void, Never>?
    private var recordingWatchdog: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?
    private var pipelineWatchdog: Task<Void, Never>?
    private var accessibilityWatch: Task<Void, Never>?

    private init() {
        history = UserDefaults.standard.stringArray(forKey: "history") ?? []
        HandyMigration.runIfNeeded(settings: settings)
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.toggle()
        }
        KeyboardShortcuts.onKeyDown(for: .cancelDictation) { [weak self] in
            self?.cancel()
        }
        KeyboardShortcuts.disable(.cancelDictation)
        watchAccessibility()
    }

    func requestAccessibility() {
        Permissions.promptAccessibility()
        Permissions.openAccessibilitySettings()
        watchAccessibility()
    }

    /// TCC has no change notification, so the permission is polled until granted,
    /// then the watcher stops for good.
    private func watchAccessibility() {
        guard !accessibilityGranted, accessibilityWatch == nil else { return }
        accessibilityWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if Permissions.accessibilityGranted {
                    self.accessibilityGranted = true
                    self.accessibilityWatch = nil
                    return
                }
            }
        }
    }

    func toggle() {
        let now = Date()
        guard now.timeIntervalSince(lastToggle) > 0.25 else { return }
        lastToggle = now

        // A press while the microphone prompt is still up means "never mind".
        if let pendingStart {
            pendingStart.cancel()
            self.pendingStart = nil
            return
        }

        switch phase {
        case .idle:
            startRecording()
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            break
        }
    }

    func cancel() {
        pendingStart?.cancel()
        pendingStart = nil
        switch phase {
        case .recording:
            recordingWatchdog?.cancel()
            recordingWatchdog = nil
            KeyboardShortcuts.disable(.cancelDictation)
            recorder.cancel()
            phase = .idle
            overlay.hide()
        case .transcribing:
            pipelineTask?.cancel()
        case .idle:
            break
        }
    }

    func copyLastTranscript() {
        guard let last = history.first else { return }
        Paster.copyPlain(last)
    }

    private func startRecording() {
        pendingStart = Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = await Permissions.requestMicrophone()
            guard !Task.isCancelled else { return }
            defer {
                if !Task.isCancelled {
                    self.pendingStart = nil
                }
            }
            guard granted else {
                self.fail("Accès micro refusé. Autorise Magneto dans Réglages Système > Confidentialité et sécurité > Microphone.")
                return
            }
            guard self.phase == .idle else { return }
            do {
                try self.recorder.start()
            } catch {
                self.fail(error.localizedDescription)
                return
            }
            self.lastError = nil
            self.phase = .recording
            KeyboardShortcuts.enable(.cancelDictation)
            self.overlay.show()
            self.recordingWatchdog = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(900))
                guard !Task.isCancelled, let self, self.phase == .recording else { return }
                self.stopAndTranscribe()
            }
        }
    }

    private func stopAndTranscribe() {
        recordingWatchdog?.cancel()
        recordingWatchdog = nil
        guard let url = recorder.stop() else {
            KeyboardShortcuts.disable(.cancelDictation)
            phase = .idle
            overlay.hide()
            return
        }
        // Duration comes from the file, not the recorder: a recorder that stopped on
        // its own (mic unplugged) reports 0 and the audio would be silently dropped.
        guard audioDuration(of: url) >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            KeyboardShortcuts.disable(.cancelDictation)
            phase = .idle
            overlay.hide()
            return
        }
        phase = .transcribing
        busyLabel = "Transcription…"
        pipelineTask = Task { @MainActor [weak self] in
            await self?.runPipeline(url: url)
        }
        pipelineWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled, let self, self.phase == .transcribing else { return }
            self.pipelineTask?.cancel()
            self.lastError = "Transcription interrompue : délai de 3 minutes dépassé."
        }
    }

    private func runPipeline(url: URL) async {
        defer {
            try? FileManager.default.removeItem(at: url)
            pipelineWatchdog?.cancel()
            pipelineWatchdog = nil
            pipelineTask = nil
            KeyboardShortcuts.disable(.cancelDictation)
            if phase == .transcribing {
                phase = .idle
            }
            overlay.hide()
        }

        let vocabulary = settings.customWords
        let result = await TranscriptionService.transcribe(
            audioURL: url,
            language: settings.language,
            vocabulary: vocabulary
        )
        guard !Task.isCancelled else { return }

        switch result {
        case .failure(let error):
            fail(error.localizedDescription)
        case .success(let transcription):
            var text = RulePass.clean(
                transcription.text,
                customWords: vocabulary,
                frenchTypography: settings.frenchTypography
            )
            if settings.postProcessEnabled, text.count >= 40 {
                busyLabel = "Nettoyage…"
                if let cleaned = try? await LLMPass.clean(
                    text,
                    provider: settings.postProcessProvider,
                    vocabulary: vocabulary,
                    aggressiveFillers: settings.aggressiveFillers
                ), LLMPass.isSane(cleaned, comparedTo: text, aggressiveFillers: settings.aggressiveFillers) {
                    text = RulePass.normalizeQuotes(cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            guard !Task.isCancelled else { return }
            guard !text.isEmpty else {
                fail("La transcription est vide.")
                return
            }
            pushHistory(text)
            let outcome = await Paster.deliver(text)
            if outcome == .copiedOnly {
                lastError = "Collage impossible sans la permission Accessibilité. Le texte est copié : fais Cmd+V."
            }
        }
    }

    private func audioDuration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return 0 }
        return Double(file.length) / rate
    }

    private func pushHistory(_ text: String) {
        history.insert(text, at: 0)
        if history.count > 10 {
            history.removeLast(history.count - 10)
        }
        UserDefaults.standard.set(history, forKey: "history")
    }

    private func fail(_ message: String) {
        lastError = message
        recordingWatchdog?.cancel()
        recordingWatchdog = nil
        KeyboardShortcuts.disable(.cancelDictation)
        phase = .idle
        overlay.hide()
        NSSound.beep()
    }
}

extension AppState.Phase {
    var menuBarSymbol: String {
        switch self {
        case .idle: return "waveform"
        case .recording: return "record.circle"
        case .transcribing: return "hourglass"
        }
    }

    var statusLabel: String {
        switch self {
        case .idle: return "Prêt"
        case .recording: return "Enregistrement…"
        case .transcribing: return "Transcription…"
        }
    }
}
