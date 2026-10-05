import ActivityKit
import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var dictation: Dictation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var keyStatus = KeyStatus()
    @ObservedObject private var ledger = UsageLedger.shared

    @State private var micGranted = true
    @State private var activitiesEnabled = true
    @State private var justCopied = false
    @State private var newWord = ""
    @State private var copiedEntry: String?
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            Form {
                status
                shortcut
                keys
                usage
                vocabulary
                text
                recent
                diagnostic
            }
            .navigationTitle("Magneto")
            .onAppear(perform: refresh)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refresh()
                }
            }
        }
    }

    // MARK: État

    /// The Mac header, as a card: what the app is doing, the one button, and the errors.
    /// Prerequisites only show while they are missing, like Accessibility on the Mac.
    private var status: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: dictation.phase.symbol)
                    .font(.title2)
                    .foregroundStyle(dictation.phase == .recording ? .red : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dictation.phase.statusLabel)
                        .font(.headline)
                    if dictation.phase == .recording {
                        Text(dictation.startedAt, style: .timer)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if justCopied {
                        Text("Texte copié")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(dictation.phase == .recording ? "Arrêter" : "Dicter") {
                    Task {
                        if let text = await dictation.toggle() {
                            UIPasteboard.general.string = text
                            justCopied = true
                            try? await Task.sleep(for: .seconds(2))
                            justCopied = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(dictation.phase == .recording ? .red : .accentColor)
                .disabled(dictation.phase == .finishing || !micGranted)
            }
            .padding(.vertical, 4)

            if let error = dictation.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if !micGranted {
                Button {
                    Task {
                        micGranted = await AVAudioApplication.requestRecordPermission()
                    }
                } label: {
                    Label("Autoriser le micro", systemImage: "mic.badge.xmark")
                }
            }
            if !activitiesEnabled {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Activer les Live Activities", systemImage: "rectangle.topthird.inset.filled")
                }
            }
        } footer: {
            if !activitiesEnabled {
                Text("Sans Live Activities, iOS coupe une dictée lancée depuis le raccourci.")
            }
        }
    }

    // MARK: Raccourci

    private var shortcut: some View {
        Section {
            if let file = Bundle.main.url(forResource: "Dicter", withExtension: "shortcut") {
                ShareLink(item: file) {
                    Label("Installer le raccourci Dicter", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Raccourci")
        } footer: {
            Text("Choisir Raccourcis dans la feuille de partage, puis l'assigner : Réglages > Bouton Action > Raccourci, ou Accessibilité > Toucher > Toucher le dos. Un appui démarre la dictée, le suivant l'arrête et copie le texte.")
        }
    }

    // MARK: Clés

    private var keys: some View {
        Section {
            Picker("Moteur", selection: $settings.engineChoice) {
                ForEach(EngineChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            KeyRow(label: "Microsoft", account: Keychain.microsoft, status: keyStatus)
            KeyRow(label: "ElevenLabs", account: Keychain.elevenLabs, status: keyStatus)
        } header: {
            Text("Clés API")
        } footer: {
            Text(EngineChoice.explanation + "\n\nBalayer une clé vers la gauche la supprime.")
        }
    }

    // MARK: Consommation

    private var usage: some View {
        Section {
            UsageRow(label: "Ce mois-ci", usage: ledger.thisMonth)
            UsageRow(label: "Mois dernier", usage: ledger.lastMonth)
            UsageRow(
                label: "Depuis le \(ledger.since.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR"))))",
                usage: ledger.sinceReset
            )
            Button("Repartir de zéro") {
                ledger.reset()
            }
        } header: {
            Text("Consommation")
        } footer: {
            Text(Usage.explanation + "\n\nCompté sur ce téléphone seulement.")
        }
    }

    // MARK: Vocabulaire

    private var hasAnyKey: Bool {
        !keyStatus.present.isEmpty
    }

    private var vocabulary: some View {
        Section {
            HStack {
                TextField("Ajouter un terme", text: $newWord)
                    .onSubmit(addWord)
                Button("Ajouter", action: addWord)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(settings.customWords, id: \.self) { word in
                Text(word)
            }
            .onDelete { offsets in
                for index in offsets {
                    settings.removeCustomWord(settings.customWords[index])
                }
            }
        } header: {
            Text("Vocabulaire")
        } footer: {
            Text(hasAnyKey
                ? "Transmis aux moteurs en ligne comme référence orthographique. \(settings.customWords.count) terme\(settings.customWords.count > 1 ? "s" : "")."
                : "Sans clé API, ces termes ne partent vers aucun moteur.")
        }
        .disabled(!hasAnyKey)
    }

    // MARK: Réglages

    private var text: some View {
        Section {
            Toggle("Guillemets droits", isOn: $settings.straightQuotes)
        } header: {
            Text("Texte")
        } footer: {
            Text("Remplace « » et les guillemets courbes par des \". C'est la seule modification apportée au texte du moteur.")
        }
    }

    private var diagnostic: some View {
        Section {
            Toggle("Journal des dictées", isOn: $settings.dictationJournal)
        } header: {
            Text("Diagnostic")
        } footer: {
            Text("Écrit chaque dictée, son audio et son texte dans Fichiers > Sur mon iPhone > Magneto. Le texte y est en clair, environ 2 Mo par minute dictée, et rien n'est écrit quand c'est décoché.\n\nMagneto \(version)")
        }
    }

    // MARK: Dictées

    /// The last dictation stays in view, since re-copying it is the whole point; the
    /// ones before fold behind one row so the screen does not grow with the day.
    private var recent: some View {
        Section {
            if let last = dictation.history.first {
                dictationRow(last)
                if dictation.history.count > 1 {
                    DisclosureGroup(isExpanded: $showHistory) {
                        ForEach(dictation.history.dropFirst(), id: \.self) { entry in
                            dictationRow(entry)
                        }
                    } label: {
                        Text("Historique (\(dictation.history.count - 1))")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Aucune dictée pour l'instant")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Dernière dictée")
        } footer: {
            Text("Toucher une dictée la copie à nouveau.")
        }
    }

    private func dictationRow(_ entry: String) -> some View {
        Button {
            UIPasteboard.general.string = entry
            copiedEntry = entry
        } label: {
            HStack {
                Text(entry)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: copiedEntry == entry ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copiedEntry == entry ? .green : .secondary)
            }
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private func refresh() {
        micGranted = AVAudioApplication.shared.recordPermission == .granted
        activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        copiedEntry = nil
        keyStatus.load()
    }

    private func addWord() {
        settings.addCustomWord(newWord)
        newWord = ""
    }
}

/// A key is almost always pasted in one go, so the field commits on its own shortly
/// after the text stops changing, and Return only shortcuts that wait. Same rules as the
/// Mac field, with the verdict written under the row since there is nothing to hover.
private struct KeyRow: View {
    /// Below this, the text cannot be a key, and probing it would only report a failure
    /// the user already knows about.
    private static let plausibleLength = 16

    let label: String
    let account: String
    @ObservedObject var status: KeyStatus

    @State private var value = ""
    @State private var pending: Task<Void, Never>?

    private var isPresent: Bool {
        status.present.contains(account)
    }

    private var isVerified: Bool {
        status.validated.contains(account)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // The label opens the page the key comes from, so nobody hunts for it with
                // a half-pasted key in the other hand.
                if let keysPage = KeyCheck.keysPage(for: account) {
                    Link(destination: keysPage) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption)
                            Text(label)
                        }
                    }
                } else {
                    Text(label)
                }
                SecureField("", text: $value, prompt: Text(isPresent ? "••••••••" : "Coller la clé"))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(commitNow)
                    .onChange(of: value) { _, typed in
                        scheduleCommit(typed)
                    }
                indicator
            }
            if let problem = status.problems[account] {
                Text(problem.message)
                    .font(.footnote)
                    .foregroundStyle(problem.blocking ? .red : .orange)
            }
        }
        .swipeActions(edge: .trailing) {
            if isPresent {
                Button("Supprimer", role: .destructive) {
                    status.remove(account)
                }
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if status.checking.contains(account) {
            ProgressView()
        } else if let problem = status.problems[account] {
            Image(systemName: problem.blocking ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(problem.blocking ? Color.red : Color.orange)
        } else {
            Image(systemName: isPresent ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isVerified ? Color.green : Color.secondary)
        }
    }

    private func scheduleCommit(_ typed: String) {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.plausibleLength else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            commit(trimmed)
        }
    }

    private func commitNow() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pending?.cancel()
        commit(trimmed)
    }

    private func commit(_ trimmed: String) {
        value = ""
        Task { await status.save(trimmed, account: account, label: label) }
    }
}

/// No hover on a phone, so the minutes and each engine's share sit under the total.
private struct UsageRow: View {
    let label: String
    let usage: Usage

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(usage.summary)
                Text(usage.detail)
                    .font(.caption)
            }
            .monospacedDigit()
        } label: {
            Text(label)
        }
    }
}
