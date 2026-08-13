import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var app: AppState
    @State private var tab: Tab = .general
    @State private var setupSkipped = false
    @State private var justCopied = false

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
            case .general: GeneralTab()
            case .vocabulary: VocabularyTab()
            case .keys: KeysTab()
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
                Text("Ouvrir les Réglages Système")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Coche Magneto dans la liste")
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
    @State private var visible = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Image(systemName: "info.circle")
            .foregroundStyle(visible ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
            .accessibilityLabel("Aide")
            .accessibilityHint(text)
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

private extension View {
    /// Draws the visible help tag above the form, clamped inside it: anchored under
    /// its icon, flipped above when the bottom edge is too close, and pushed left
    /// when it would run past the panel.
    func helpTagOverlay() -> some View {
        overlayPreferenceValue(HelpTagKey.self) { position in
            GeometryReader { proxy in
                if let position {
                    let icon = proxy[position.anchor]
                    let width: CGFloat = 230
                    let height: CGFloat = 44
                    let margin: CGFloat = 10
                    let below = icon.maxY + 6
                    let fitsBelow = below + height + margin <= proxy.size.height
                    Text(position.text)
                        .font(.callout)
                        .padding(.horizontal, 9)
                        .frame(width: width, height: height, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
                        .offset(
                            x: min(max(margin, icon.minX - 6), proxy.size.width - width - margin),
                            y: fitsBelow ? below : max(margin, icon.minY - height - 6)
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
                }
                .disabled(providersWithKey.isEmpty)
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
                    Text("Demande une clé Mistral ou Anthropic, à saisir dans l'onglet Clés API.")
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
    @EnvironmentObject private var settings: AppSettings
    @State private var newWord = ""
    @State private var selection: String?

    var body: some View {
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
            // Placed under the controls it describes, where the grouped forms of the
            // other tabs put their own explanations.
            Text("Ces termes sont transmis au moteur de transcription et servent de référence orthographique au nettoyage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // The list grows with the vocabulary, so this tab is the one place that
        // needs a set height rather than its content's.
        .frame(height: 290)
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
    var body: some View {
        Form {
            Section {
                KeyField(
                    label: "ElevenLabs",
                    help: "Scribe v2, moteur principal",
                    account: Keychain.elevenLabs
                )
                KeyField(
                    label: "Mistral",
                    help: "Voxtral en secours, sert aussi au nettoyage",
                    account: Keychain.mistral
                )
            } header: {
                Text("Transcription")
            } footer: {
                Text("Sans aucune clé, le moteur Apple hors ligne prend le relais.")
            }

            Section {
                KeyField(
                    label: "Anthropic",
                    help: "Claude Haiku, alternative à Mistral Small",
                    account: Keychain.anthropic
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
    }
}

/// A settings window is modeless on macOS: no Save button, the value is committed
/// when the field is validated or loses focus.
private struct KeyField: View {
    let label: String
    let help: String
    let account: String

    @State private var value = ""
    @State private var present = false
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                SecureField(
                    label,
                    text: $value,
                    prompt: Text(present ? "••••••••" : "Coller la clé")
                )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .focused($focused)
                    .onSubmit(save)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { save() }
                    }
                Image(systemName: present ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(present ? Color.green : Color.secondary)
                    .help(present ? "Clé enregistrée" : "Aucune clé enregistrée")
            }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                HelpTag(help)
            }
        }
        .onAppear {
            present = Keychain.exists(account)
        }
    }

    private func save() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Keychain.set(trimmed, account: account, label: label)
        value = ""
        present = Keychain.exists(account)
    }
}
