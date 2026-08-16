import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var app: AppState
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
            case .general: GeneralTab(onOpenKeys: { tab = .keys })
            case .vocabulary: VocabularyTab(onOpenKeys: { tab = .keys })
            case .keys: KeysTab(status: keyStatus)
            }
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
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
            .help("Copier la dernière transcription")
        }
    }

    private var footer: some View {
        HStack {
            Text("Magneto \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Text("Magneto colle le texte dicté là où se trouve ton curseur. macOS exige pour cela l'autorisation Accessibilité.")
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
                Text("1. Ouvre les réglages depuis la fenêtre macOS, puis coche Magneto")
                Text("2. Reviens ici, la fenêtre se met à jour toute seule")
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
    let onOpenKeys: () -> Void

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Read on appear, not on every redraw: keys are edited from another tab.
    @State private var providersWithKey: [PostProcessProvider] = []

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
                // Shown off, not ticked-but-greyed: a ticked box that produces
                // nothing is what made this option misleading. The stored choice
                // is kept, so adding a key brings it back as it was.
                HelpRow("Activer", help: "Retire les hésitations, corrige ponctuation et nombres") {
                    Toggle(
                        "",
                        isOn: providersWithKey.isEmpty ? Binding.constant(false) : $settings.postProcessEnabled
                    )
                    .labelsHidden()
                    // Only the switch is disabled. Disabling the whole row killed the
                    // help tag with it, hiding what the option does exactly when it
                    // cannot be turned on and the question is most likely.
                    .disabled(providersWithKey.isEmpty)
                }
                // Dimming rather than disabling: the system disabled state alone is too
                // discreet, the switch being already off, and opacity leaves the help
                // tag reachable.
                .opacity(providersWithKey.isEmpty ? 0.45 : 1)
                if !providersWithKey.isEmpty, settings.postProcessEnabled {
                    // Every model stays listed, so the second one advertises itself
                    // as available once its key is filled in.
                    Picker("Modèle", selection: $settings.postProcessProvider) {
                        ForEach(PostProcessProvider.allCases) { provider in
                            Text(providersWithKey.contains(provider) ? provider.label : "\(provider.label) (clé requise)")
                                .disabled(!providersWithKey.contains(provider))
                                .tag(provider)
                        }
                    }
                    // Enforces the greyed rows: a keyless model never sticks, even
                    // if the popup lets it be picked.
                    .onChange(of: settings.postProcessProvider) { previous, selected in
                        if !providersWithKey.contains(selected) {
                            settings.postProcessProvider = previous
                        }
                    }
                    HelpRow("Retirer les connecteurs", help: "Retire les connecteurs creux : du coup, en fait, genre, voilà") {
                        Toggle("", isOn: $settings.aggressiveFillers)
                            .labelsHidden()
                    }
                }
            } header: {
                Text("Nettoyage par IA")
            } footer: {
                if providersWithKey.isEmpty {
                    KeyRequiredNotice(
                        text: "Pour activer cette fonctionnalité, une clé API de nettoyage est nécessaire, à saisir dans l'onglet [Clés API](magneto:keys).",
                        onOpenKeys: onOpenKeys
                    )
                }
            }

            // Its own section: it runs on rules, always, with or without a key, and
            // grouping it under the IA suggested a dependency that does not exist.
            Section {
                HelpRow("Typographie française", help: "Écrit « Tu viens ? » plutôt que « Tu viens? »") {
                    Toggle("", isOn: $settings.frenchTypography)
                        .labelsHidden()
                }
            } header: {
                Text("Typographie")
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
        .helpTagOverlay()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            providersWithKey = PostProcessProvider.allCases.filter { Keychain.exists($0.keychainAccount) }
            // A key removed after being selected would leave the picker on a model
            // that silently cannot run.
            if let fallback = providersWithKey.first, !providersWithKey.contains(settings.postProcessProvider) {
                settings.postProcessProvider = fallback
            }
        }
    }
}

private struct VocabularyTab: View {
    let onOpenKeys: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @State private var newWord = ""
    @State private var selection: String?
    /// Vocabulary reaches an engine as ElevenLabs keyterms, Voxtral context bias or
    /// the cleanup prompt. Without a single key it goes nowhere, and a list that looks
    /// live is worse than one that says it is not.
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
                Text("Ces termes sont transmis au moteur de transcription et servent de référence orthographique au nettoyage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } else {
                KeyRequiredNotice(
                    text: "Sans clé API, ces termes ne partent vers aucun moteur. Ajoute une clé dans l'onglet [Clés API](magneto:keys).",
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
            hasAnyKey = Keychain.exists(Keychain.elevenLabs)
                || Keychain.exists(Keychain.mistral)
                || Keychain.exists(Keychain.anthropic)
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

/// Shared by every field rather than held in each one: Mistral is listed in both
/// sections, so a key pasted in one has to light up the other. Both rows write the
/// same keychain item, there is still only one secret.
@MainActor
private final class KeyStatus: ObservableObject {
    @Published private(set) var present: Set<String> = []
    @Published private(set) var checking: Set<String> = []
    struct Problem {
        let message: String
        /// A refused key needs a new one, an exhausted quota needs patience. Sending
        /// someone to re-paste a perfectly good key helps nobody.
        let blocking: Bool
    }

    @Published private(set) var problems: [String: Problem] = [:]
    /// Only keys actually probed in this session. Reopening the tab reloads presence
    /// but probes nothing, and a green tick claiming validity would then be a guess.
    @Published private(set) var validated: Set<String> = []

    private static let accounts = [Keychain.elevenLabs, Keychain.mistral, Keychain.anthropic]

    /// Probes anything still without a verdict, so opening the tab is enough to know
    /// where each key stands. A verdict is kept for the whole session, so this costs
    /// one request per key per launch. A previous failure is retried, since it may
    /// have been the network rather than the key.
    func load() {
        present = Set(Self.accounts.filter { Keychain.exists($0) })
        for account in present where !validated.contains(account) && !checking.contains(account) {
            guard let key = Keychain.get(account) else { continue }
            Task { await verify(key, account: account) }
        }
    }

    func save(_ key: String, account: String, label: String) async {
        Keychain.set(key, account: account, label: label)
        guard Keychain.exists(account) else { return }
        present.insert(account)
        await verify(key, account: account)
    }

    private func verify(_ key: String, account: String) async {
        problems[account] = nil
        validated.remove(account)
        checking.insert(account)
        let outcome = await KeyCheck.run(account: account, key: key)
        checking.remove(account)
        switch outcome {
        case .valid:
            validated.insert(account)
        case .unusable(let reason):
            problems[account] = Problem(message: reason, blocking: false)
        case .refused(let reason):
            problems[account] = Problem(message: reason, blocking: true)
        }
    }
}

private struct KeysTab: View {
    @ObservedObject var status: KeyStatus

    var body: some View {
        Form {
            Section {
                KeyField(
                    label: "ElevenLabs",
                    help: "Scribe v2, moteur principal",
                    account: Keychain.elevenLabs,
                    status: status
                )
                KeyField(
                    label: "Mistral",
                    help: "Voxtral, moteur de secours. Même clé que le nettoyage",
                    account: Keychain.mistral,
                    status: status
                )
            } header: {
                Text("Transcription")
            } footer: {
                Text("Sans aucune clé, le moteur Apple hors ligne prend le relais.")
            }

            // Mistral kept in second position, as in the section above: the same key
            // then sits on the same row in both, which shows the link without a word.
            Section {
                KeyField(
                    label: "Anthropic",
                    help: "Claude Haiku",
                    account: Keychain.anthropic,
                    status: status
                )
                KeyField(
                    label: "Mistral",
                    help: "Mistral Small. Même clé que la transcription",
                    account: Keychain.mistral,
                    status: status
                )
            } header: {
                Text("Nettoyage")
            } footer: {
                Text("Clés stockées dans le trousseau macOS.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .helpTagOverlay()
        .onAppear { status.load() }
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
            }
        } label: {
            HStack(spacing: 5) {
                Text(label)
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
