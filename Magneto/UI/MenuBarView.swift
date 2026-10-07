import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var updater: Updater
    @State private var tab: Tab = .general
    @State private var setupSkipped = false
    @State private var justCopied = false
    /// Owned here rather than by the tab: a verdict obtained once must survive leaving
    /// the tab, otherwise every return showed keys as unverified again.
    @StateObject private var keyStatus = KeyStatus()

    private enum Tab: String, CaseIterable, Identifiable {
        case general = "Général"
        case vocabulary = "Vocabulaire"
        case keys = "Clés API"

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if app.accessibilityGranted || setupSkipped {
                mainContent
            } else {
                AccessibilitySetup(onSkip: { setupSkipped = true })
                    .padding(16)
            }
        }
        .frame(width: 380)
        .background(FocusSink())
        // Closing the popover only hides it, so the tab has to be reset by hand.
        .onAppear { tab = .general }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            if let error = app.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            Picker("Onglet", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            // Each tab sets its own height: a form must never scroll to show its rows.
            switch tab {
            case .general: GeneralTab()
            case .vocabulary: VocabularyTab(onOpenKeys: { tab = .keys })
            case .keys: KeysTab(status: keyStatus)
            }
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        // One layer for the whole popover rather than one per tab: the header's Copier
        // carries a bubble too, and a layer per tab would draw a tab's bubble twice.
        .helpTagOverlay()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: app.phase.menuBarSymbol)
                .foregroundStyle(app.phase == .recording ? .red : .secondary)
            Text(app.phase.statusLabel)
                .font(.headline)
            Spacer()
            Button(app.phase == .recording ? "Arrêter" : "Dicter") {
                app.toggle()
            }
            .disabled(app.phase == .transcribing)
            Button {
                app.copyLastTranscript()
                justCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    justCopied = false
                }
            } label: {
                Label(
                    justCopied ? "Copié" : "Copier",
                    systemImage: justCopied ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(app.history.isEmpty)
            .helpBubble("Copier la dernière transcription")
        }
    }

    /// Displayed only, so it is read where it is shown rather than through a type of
    /// its own.
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Magneto \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let pending = updater.pendingVersion {
                Button("Mettre à jour vers \(pending)") {
                    updater.check()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.caption)
            } else {
                Button("Vérifier les mises à jour") {
                    updater.check()
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(!updater.canCheck)
            }
            Spacer()
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

/// Shown instead of the whole popover until Accessibility is granted: without it
/// the transcript can only be copied, never pasted, which is easy to miss when
/// the warning sits at the bottom of a settings tab.
private struct AccessibilitySetup: View {
    let onSkip: () -> Void

    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Autorisation requise")
                    .font(.headline)
            }
            Text("Magneto colle le texte dicté là où se trouve votre curseur. macOS exige pour cela l'autorisation Accessibilité.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                app.requestAccessibility()
            } label: {
                Text("Autoriser Magneto")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Ouvrez les réglages depuis la fenêtre macOS, puis cochez Magneto")
                Text("2. Revenez ici, la fenêtre se met à jour toute seule")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("En attente de l'autorisation…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continuer sans", action: onSkip)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}

/// A settings row whose label carries a help tag, placed right after the title.
private struct HelpRow<Content: View>: View {
    private let title: String
    private let help: String
    private let content: () -> Content

    init(_ title: String, help: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.help = help
        self.content = content
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            HelpTag(help)
            Spacer(minLength: 12)
            content()
        }
    }
}

/// Explains why a section is inert. The link is markdown inside the sentence rather
/// than a separate button, and its scheme is never opened: `OpenURLAction` intercepts
/// the tap to switch tabs.
private struct KeyRequiredNotice: View {
    let text: LocalizedStringKey
    let onOpenKeys: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "key.fill")
                .foregroundStyle(.orange)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .environment(\.openURL, OpenURLAction { _ in
            onOpenKeys()
            return .handled
        })
    }
}

/// Takes the popover's focus each time it opens, so the shortcut recorder, its first
/// editable control, is only focused by a click. Given the window's initial focus, it
/// started recording on open and the next key typed replaced the shortcut. Its own
/// guard, `canBecomeKeyView` off for one turn, loses the race against SwiftUI.
private struct FocusSink: NSViewRepresentable {
    func makeNSView(context: Context) -> Sink { Sink() }
    func updateNSView(_ nsView: Sink, context: Context) {}

    final class Sink: NSView {
        private var observer: NSObjectProtocol?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return }
            window.initialFirstResponder = self
            claim()
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.claim() }
            }
        }

        /// Run now and again on the next turn, after AppKit and SwiftUI have placed their
        /// own initial focus. A field the person is typing in is left alone, and so is a
        /// click inside the popover: it makes the window key too, and taking the focus
        /// back then would end the recording that very click just started.
        private func claim() {
            if let event = NSApp.currentEvent, event.window === window,
               [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp].contains(event.type) {
                return
            }
            take()
            DispatchQueue.main.async { [weak self] in self?.take() }
        }

        private func take() {
            guard let window else { return }
            let responder = window.firstResponder
            let editing: AnyObject? = (responder as? NSTextView)?.delegate ?? responder
            guard responder == nil || responder === window || editing is KeyboardShortcuts.RecorderCocoa else { return }
            window.makeFirstResponder(self)
        }
    }
}

/// macOS only draws system tooltips for the focused window, and the menu bar panel
/// never takes focus, so `.help()` stays silent here and the help tag is drawn by
/// hand. Wording follows the HIG: one short sentence, starting with a verb, about
/// this control only.
///
/// The tag reports its position instead of drawing the bubble itself: a `Form` gives
/// no way to raise one row above the next, so the bubble is drawn by `helpTagOverlay`
/// on top of the whole form.
private struct HelpTag: View {
    private let text: String
    @State private var hovering = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Image(systemName: "info.circle")
            .foregroundStyle(hovering ? Color.accentColor : Color.secondary)
            .accessibilityLabel("Aide")
            .accessibilityHint(text)
            .onHover { hovering = $0 }
            .helpBubble(text)
    }
}

/// Carries the hand-drawn bubble on any view. The system tooltip takes about three
/// seconds to appear, which is far too slow for a status light one glances at.
private struct HelpBubble: ViewModifier {
    let text: String
    @State private var hovering = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                guard inside else {
                    visible = false
                    return
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard hovering else { return }
                    visible = true
                }
            }
            .anchorPreference(key: HelpTagKey.self, value: .bounds) { anchor in
                visible ? HelpTagPosition(text: text, anchor: anchor) : nil
            }
    }
}

private extension View {
    func helpBubble(_ text: String) -> some View {
        modifier(HelpBubble(text: text))
    }
}

private struct HelpTagPosition {
    let text: String
    let anchor: Anchor<CGRect>
}

private struct HelpTagKey: PreferenceKey {
    static let defaultValue: HelpTagPosition? = nil

    static func reduce(value: inout HelpTagPosition?, nextValue: () -> HelpTagPosition?) {
        value = value ?? nextValue()
    }
}

/// Matches the look of a macOS tooltip: 11 pt text, tight padding, small radius and a
/// discreet shadow. The size is measured rather than left to SwiftUI, because the
/// bubble is positioned by hand and its dimensions must be known before it is drawn.
private enum HelpBubbleStyle {
    static let maxWidth: CGFloat = 220
    static let radius: CGFloat = 5
    static let horizontalPadding: CGFloat = 7
    static let verticalPadding: CGFloat = 4
    static let font = NSFont.systemFont(ofSize: 11)

    static func size(for text: String) -> CGSize {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth - horizontalPadding * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return CGSize(
            width: ceil(bounds.width) + horizontalPadding * 2,
            height: ceil(bounds.height) + verticalPadding * 2
        )
    }
}

private extension View {
    /// Draws the visible help tag above the form, clamped inside it: anchored under
    /// its icon, flipped above when the bottom edge is too close, and pushed left
    /// when it would run past the panel.
    func helpTagOverlay() -> some View {
        overlayPreferenceValue(HelpTagKey.self) { position in
            GeometryReader { proxy in
                if let position {
                    let icon = proxy[position.anchor]
                    let size = HelpBubbleStyle.size(for: position.text)
                    let margin: CGFloat = 8
                    let below = icon.maxY + 5
                    let fitsBelow = below + size.height + margin <= proxy.size.height
                    Text(position.text)
                        .font(.system(size: 11))
                        .padding(.horizontal, HelpBubbleStyle.horizontalPadding)
                        .padding(.vertical, HelpBubbleStyle.verticalPadding)
                        // Width forced, height free: the measured height only decides
                        // where the bubble goes, and imposing it truncated any text
                        // whose real layout needed a point more than the estimate.
                        .frame(width: size.width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HelpBubbleStyle.radius))
                        .overlay(
                            RoundedRectangle(cornerRadius: HelpBubbleStyle.radius)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                        .offset(
                            x: min(max(margin, icon.minX - 4), max(margin, proxy.size.width - size.width - margin)),
                            y: fitsBelow ? below : max(margin, icon.minY - size.height - 5)
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct GeneralTab: View {

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                HelpRow("Raccourci", help: "Démarre et arrête la dictée, Échap annule l'enregistrement") {
                    KeyboardShortcuts.Recorder(for: .toggleDictation)
                }
                Picker("Fenêtre d'enregistrement", selection: $settings.overlayPosition) {
                    ForEach(OverlayPosition.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }
                HelpRow("Caps Lock sans délai", help: "Active Caps Lock dès l'appui, sans attendre") {
                    Toggle("", isOn: $settings.capsLockNoDelay)
                        .labelsHidden()
                }
                Toggle("Lancer au démarrage", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section {
                HelpRow(
                    "Guillemets droits",
                    help: "Remplace « » et les guillemets courbes par des \". C'est la seule modification apportée au texte du moteur : décoché, il est collé tel quel"
                ) {
                    Toggle("", isOn: $settings.straightQuotes)
                        .labelsHidden()
                }
            } header: {
                Text("Texte")
            }

            // Its own section, and worded plainly: this is the only setting that writes
            // what was dictated to the disk, and someone ticking it deserves to know
            // before rather than after.
            Section {
                HelpRow(
                    "Journal des dictées",
                    help: "Écrit chaque dictée, son audio et son texte avant et après les règles dans ~/Library/Application Support/Magneto. Le texte y est en clair, compte environ 2 Mo par minute dictée, et rien n'est écrit quand c'est décoché"
                ) {
                    Toggle("", isOn: $settings.dictationJournal)
                        .labelsHidden()
                }
                if settings.dictationJournal {
                    Button("Ouvrir le dossier du journal") {
                        if let folder = DictationJournal.directory() {
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(folder)
                        }
                    }
                    .buttonStyle(.link)
                }
            } header: {
                Text("Diagnostic")
            }

            if !app.accessibilityGranted {
                Section {
                    LabeledContent("Accessibilité") {
                        Button("Autoriser") {
                            app.requestAccessibility()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        // A grouped form is scrollable, so it takes every point it is offered
        // instead of stopping at its rows. This pins it to their height.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct VocabularyTab: View {
    let onOpenKeys: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @State private var newWord = ""
    @State private var selection: String?
    /// Vocabulary reaches an engine as ElevenLabs keyterms, or as the cleanup prompt.
    /// Without a single key it goes nowhere, and a list that looks live is worse than
    /// one that says it is not.
    @State private var hasAnyKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Ajouter un terme", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Ajouter", action: add)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                // macOS convention: rows stay plain and removal happens through a
                // button bar under the list, which also keeps the scrollbar from
                // sitting on top of per-row controls.
                List(selection: $selection) {
                    ForEach(settings.customWords, id: \.self) { word in
                        Text(word)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .onDeleteCommand(perform: removeSelected)
                .frame(maxHeight: .infinity)
                HStack(spacing: 6) {
                    GradientButton(
                        symbol: "minus",
                        label: "Retirer le terme sélectionné",
                        isEnabled: selection != nil,
                        action: removeSelected
                    )
                    .frame(width: 24, height: 22)
                    Spacer()
                    Text("\(settings.customWords.count) terme\(settings.customWords.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!hasAnyKey)
            .opacity(hasAnyKey ? 1 : 0.45)

            // Kept outside the block above, otherwise the link would be disabled too.
            if hasAnyKey {
                Text("Ces termes sont transmis aux moteurs en ligne comme référence orthographique.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
                KeyRequiredNotice(
                    text: "Sans clé API, ces termes ne partent vers aucun moteur. Ajoutez une clé dans l'onglet [Clés API](magneto:keys).",
                    onOpenKeys: onOpenKeys
                )
                .font(.caption)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // The list grows with the vocabulary, so this tab is the one place that
        // needs a set height rather than its content's.
        .frame(height: 290)
        .onAppear {
            hasAnyKey = Keychain.exists(Keychain.elevenLabs) || Keychain.exists(Keychain.microsoft)
        }
    }

    private func add() {
        settings.addCustomWord(newWord)
        newWord = ""
    }

    private func removeSelected() {
        guard let selection else { return }
        settings.removeCustomWord(selection)
        self.selection = nil
    }
}

/// AppKit's gradient button, which its documentation names as the control that
/// "initiates an action related to a view, like adding or removing rows in a table".
/// SwiftUI exposes no equivalent style. Its bezel hugs the glyph (15.5 x 13 for a
/// minus), exactly like the SwiftUI approximations do, so the caller sets the size.
private struct GradientButton: NSViewRepresentable {
    let symbol: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .smallSquare
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.title = ""
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func fire() {
            action()
        }
    }
}

private struct KeysTab: View {
    @ObservedObject var status: KeyStatus
    @ObservedObject private var ledger = UsageLedger.shared
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                HelpRow(
                    "Moteur",
                    help: EngineChoice.explanation
                ) {
                    Picker("", selection: $settings.engineChoice) {
                        ForEach(EngineChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .labelsHidden()
                }
                KeyField(
                    label: "Microsoft",
                    help: """
                    MAI-Transcribe-2 : environ une seconde pour une minute d'audio, garde davantage les hésitations

                    Créez la ressource Azure Speech en North Europe.
                    """,
                    account: Keychain.microsoft,
                    status: status
                )
                KeyField(
                    label: "ElevenLabs",
                    help: "Scribe v2 : le texte le plus propre, plus lent sur les longues dictées",
                    account: Keychain.elevenLabs,
                    status: status
                )
            } header: {
                Text("Transcription")
            } footer: {
                Text(footer)
            }

            Section {
                HelpRow("Ce mois-ci", help: Usage.explanation) {
                    UsageSummary(usage: ledger.thisMonth)
                }
                LabeledContent("Mois dernier") {
                    UsageSummary(usage: ledger.lastMonth)
                }
                LabeledContent {
                    UsageSummary(usage: ledger.sinceReset)
                } label: {
                    HStack(spacing: 5) {
                        Text("Depuis le \(ledger.since.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR"))))")
                        Button {
                            ledger.reset()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .helpBubble("Repartir de zéro à partir d'aujourd'hui")
                    }
                }
            } header: {
                Text("Consommation")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { status.load() }
    }

    /// Said plainly when a key the choice relies on is missing, since the choice then
    /// does not do what it says.
    private var footer: String {
        let missing = Engine.allCases.filter { !status.present.contains($0.account) }
        if missing.count == Engine.allCases.count {
            return "Sans clé, le moteur Apple hors ligne prend le relais."
        }
        if settings.engineChoice == .race, let absent = missing.first {
            return "La course demande les deux clés : sans clé \(absent.label), l'autre moteur répond seul."
        }
        if settings.engineChoice != .race, missing.contains(settings.engineChoice.primary) {
            return "Sans clé \(settings.engineChoice.label), l'autre moteur répond seul."
        }
        return "Sans clé, le moteur Apple hors ligne prend le relais."
    }
}

/// "12 dictées · 0,05 $", the minutes and each engine's share on hover.
private struct UsageSummary: View {
    let usage: Usage

    var body: some View {
        Text(usage.summary)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .helpBubble(usage.detail)
    }
}

/// A settings window is modeless on macOS: no Save button. A key is almost always
/// pasted in one go, so the field commits on its own shortly after the text stops
/// changing, and Return or leaving the field only shortcuts that wait.
private struct KeyField: View {
    /// Below this, the text cannot be a key from any of the three providers, and
    /// probing it would just report a failure the user already knows about.
    private static let plausibleLength = 16

    let label: String
    let help: String
    let account: String
    @ObservedObject var status: KeyStatus

    @State private var value = ""
    @State private var pending: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var isPresent: Bool {
        status.present.contains(account)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                SecureField(
                    label,
                    text: $value,
                    prompt: Text(isPresent ? "••••••••" : "Coller la clé")
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .focused($focused)
                .onSubmit(commitNow)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commitNow() }
                }
                .onChange(of: value) { _, typed in
                    scheduleCommit(typed)
                }
                indicator
                if isPresent {
                    Button {
                        pending?.cancel()
                        value = ""
                        status.remove(account)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .helpBubble("Supprimer la clé \(label)")
                }
            }
        } label: {
            HStack(spacing: 5) {
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
                    .helpBubble("Ouvrir la page des clés \(label)")
                } else {
                    Text(label)
                }
                HelpTag(help)
            }
        }
        // Switching tabs tears the field down before it ever loses focus, which used
        // to drop a pasted key without a trace.
        .onDisappear(perform: commitNow)
    }

    @ViewBuilder
    private var indicator: some View {
        if status.checking.contains(account) {
            ProgressView()
                .controlSize(.small)
                .helpBubble("Vérification de la clé…")
        } else if let problem = status.problems[account] {
            Image(systemName: problem.blocking ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(problem.blocking ? Color.red : Color.orange)
                .helpBubble(problem.message)
        } else {
            // Three distinct looks, because the difference between "stored" and
            // "checked" must not depend on hovering to be understood.
            Image(systemName: isPresent ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isVerified ? Color.green : Color.secondary)
                .helpBubble(restingHelp)
        }
    }

    private var isVerified: Bool {
        status.validated.contains(account)
    }

    private var restingHelp: String {
        guard isPresent else { return "Aucune clé enregistrée" }
        return isVerified ? "Clé valide" : "Clé enregistrée, pas encore vérifiée"
    }

    private func scheduleCommit(_ typed: String) {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        // Tested before cancelling: clearing the field re-enters here, and cancelling
        // on the way out would kill the very task doing the work.
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

    /// The check runs in a task of its own, detached from the debounce: cancelling the
    /// debounce must never abort a request already in flight, which reported a network
    /// failure for a key that had in fact just been stored.
    private func commit(_ trimmed: String) {
        value = ""
        Task { await status.save(trimmed, account: account, label: label) }
    }
}
