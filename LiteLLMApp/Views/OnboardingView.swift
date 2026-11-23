import SwiftUI

/// État persistant de l'assistant de premier lancement.
public enum OnboardingState {
    private static let key = "hasCompletedOnboarding"
    public static var hasCompleted: Bool { UserDefaults.standard.bool(forKey: key) }
    public static func complete() { UserDefaults.standard.set(true, forKey: key) }
    public static func reset() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Assistant guidé de premier lancement : choix de la langue, du fournisseur,
/// de la clé API et du modèle, installation/démarrage du proxy, test, puis
/// copie de la configuration pour les outils externes.
struct OnboardingView: View {
    @EnvironmentObject private var proxy: ProxyManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    /// Appelé quand l'utilisateur choisit « Ouvrir le chat ».
    var onOpenChat: (() -> Void)? = nil

    private enum Step: Int, CaseIterable {
        case welcome, provider, credentials, setup, test, done
    }

    private enum TestState: Equatable {
        case idle, testing, ok(String), failed(String)
    }

    @State private var step: Step = .welcome
    @State private var draft = ProxyModel()
    @State private var chosenPreset: ProviderPreset = ProviderPresets.custom
    @State private var setupBusy = false
    @State private var testState: TestState = .idle
    @State private var copied = false

    private var t: (String) -> String { L10n.shared.t }
    private func tf(_ key: String, _ args: CVarArg...) -> String { L10n.shared.t(key, args) }

    /// Nom du modèle exposé (celui qui sera testé et copié).
    private var exposedModel: String {
        draft.name.isEmpty ? draft.providerModel : draft.name
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                stepContent
                    .padding(24)
                    .frame(maxWidth: .infinity)
            }
            Divider()
            footer
                .padding()
        }
        .frame(minWidth: 680, minHeight: 620)
    }

    // MARK: - En-tête

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(t(stepTitle))
                    .font(.title2.bold())
                Text(tf("Étape %@ sur %@", step.rawValue + 1, Step.allCases.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(t("Passer")) { finish() }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var stepTitle: String {
        switch step {
        case .welcome: return t("Bienvenue dans LiteLLM-App")
        case .provider: return t("Choisissez votre fournisseur d'IA")
        case .credentials: return t("Indiquez votre clé API et le modèle à utiliser")
        case .setup: return t("Installation et démarrage du proxy")
        case .test: return t("Test de votre configuration")
        case .done: return t("C'est prêt !")
        }
    }

    // MARK: - Contenu des étapes

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .provider: providerStep
        case .credentials: credentialsStep
        case .setup: setupStep
        case .test: testStep
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(t("Cette application peut :")).font(.headline)
            Label(t("Discuter avec l'IA directement dans cette app"), systemImage: "bubble.left.and.bubble.right")
            Label(t("Brancher vos outils existants sur n'importe quel fournisseur (OpenAI, Anthropic, Gemini, Mistral…) : le proxy convertit automatiquement les API."), systemImage: "arrow.triangle.2.circlepath")
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text(t("Langue"))
                Picker(t("Langue"), selection: Binding(
                    get: { L10n.shared.lang },
                    set: { L10n.shared.lang = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            SecureField(t("Coller la clé API"), text: Binding(
                get: { draft.apiKey },
                set: { new in
                    draft.apiKey = new
                    if let p = ProviderPresets.detect(fromAPIKey: new) {
                        chosenPreset = p
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .help(tf("Détecté : %@ — utiliser ce fournisseur ?", chosenPreset.displayName))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 12)], spacing: 12) {
                ForEach(ProviderPresets.all) { p in
                    Button {
                        chosenPreset = p
                        applyPresetToDraft(p)
                        step = .credentials
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: p.systemImage)
                                .font(.title)
                            Text(t(p.displayName))
                                .font(.headline)
                                .multilineTextAlignment(.center)
                            if !p.requiresAPIKey {
                                Text(t("Ce fournisseur n'a pas besoin de clé API."))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(chosenPreset.id == p.id ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                            chosenPreset.id == p.id ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderFormView(model: $draft, initialPreset: chosenPreset)
                .frame(maxHeight: 420)
        }
    }

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: proxy.isRunning ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(proxy.isRunning ? .green : .secondary)
                Text(proxy.isRunning ? t("Le proxy est en cours d'exécution.") : t("Démarrez le proxy avec le bouton ci-dessous."))
                    .font(.headline)
            }
            if setupBusy || proxy.isBusy {
                ProgressView()
                Text(proxy.isInstalled ? t("Installation terminée, démarrage…") : t("Installation en cours…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !proxy.installLog.isEmpty {
                logBox(t("Journal d'installation"), proxy.installLog)
            }
            if !proxy.proxyLog.isEmpty {
                logBox(t("Journal du proxy"), proxy.proxyLog)
            }
        }
    }

    private func logBox(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: .constant(text))
                .font(.system(.caption2, design: .monospaced))
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }
    }

    private var testStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tf("Modèle testé : %@", exposedModel))
                .font(.headline)
            switch testState {
            case .idle:
                Text(t("Envoyez un message test pour vérifier que la clé et le modèle fonctionnent."))
                    .foregroundStyle(.secondary)
            case .testing:
                HStack { ProgressView(); Text(t("Test en cours…")) }
            case .ok(let reply):
                Label(tf("Réponse reçue : %@", reply), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(t("Le test a réussi : votre clé et votre modèle fonctionnent."))
                    .font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Label(tf("Échec du test : %@", message), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(t("Vérifiez la clé API et le modèle, puis réessayez."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(t("C'est prêt !"), systemImage: "checkmark.seal.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)
            Text(tf("Fournisseur : %@ — Modèle : %@", chosenPreset.displayName, exposedModel))
            if let url = proxy.baseURL {
                Text(tf("Base URL : %@", url.absoluteString))
                    .font(.system(.body, design: .monospaced))
            }
            if copied {
                Label(t("Configuration copiée dans le presse-papiers."), systemImage: "doc.on.doc.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Pied de page

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button(t("Précédent")) { previous() }
            }
            Spacer()
            switch step {
            case .welcome:
                Button(t("Commencer")) { step = .provider }.keyboardShortcut(.return)
            case .provider:
                Button(t("Suivant")) {
                    applyPresetToDraft(chosenPreset)
                    step = .credentials
                }
                .keyboardShortcut(.return)
            case .credentials:
                Button(t("Suivant")) {
                    commitDraft()
                    step = .setup
                }
                .disabled(!isDraftValid)
                .keyboardShortcut(.return)
            case .setup:
                Button(setupButtonTitle) { Task { await runSetup() } }
                    .disabled(setupBusy || proxy.isBusy || proxy.isRunning)
                Button(t("Suivant")) { step = .test }
                    .disabled(!proxy.isRunning)
            case .test:
                Button(t("Envoyer un message test")) { Task { await runTest() } }
                    .disabled(testState == .testing || !proxy.isRunning)
                if case .failed = testState {
                    Button(t("Réessayer")) { Task { await runTest() } }
                }
                Button(t("Suivant")) { step = .done }
            case .done:
                Button(t("Copier la configuration pour mes autres outils")) { copyConfig() }
                Button(t("Utiliser dans cette app")) { applyToApp() }
                Button(t("Ouvrir le chat")) { finish(openChat: true) }
                    .keyboardShortcut(.return)
            }
        }
    }

    // MARK: - Actions

    private var isDraftValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !draft.providerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (!chosenPreset.requiresAPIKey || !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func applyPresetToDraft(_ p: ProviderPreset) {
        let bare = ProviderPresets.bareModelID(from: draft.providerModel)
        let modelID = p.knownModels.contains(where: { $0.id == bare })
            ? bare
            : (p.knownModels.first?.id ?? bare)
        draft.providerModel = p.litellmPrefix + modelID
        if !p.defaultAPIBase.isEmpty && draft.apiBase.isEmpty {
            draft.apiBase = p.defaultAPIBase
        }
        if draft.name.isEmpty { draft.name = modelID }
    }

    /// Ajoute le brouillon aux modèles du proxy (sans doublon).
    private func commitDraft() {
        guard isDraftValid else { return }
        if !proxy.settings.models.contains(where: { $0.id == draft.id }) {
            proxy.settings.models.append(draft)
            proxy.saveSettings()
        }
    }

    private var setupButtonTitle: String {
        if !proxy.isInstalled { return t("Lancer l'installation (quelques minutes la première fois)") }
        if !proxy.isRunning { return t("Démarrer le proxy") }
        return t("Le proxy est en cours d'exécution.")
    }

    private func runSetup() async {
        setupBusy = true
        defer { setupBusy = false }
        commitDraft()
        if !proxy.isInstalled {
            _ = await proxy.installAndWait()
        }
        if proxy.isInstalled && !proxy.isRunning {
            _ = await proxy.startAndWait()
        }
    }

    private func runTest() async {
        testState = .testing
        guard let url = proxy.baseURL else {
            testState = .failed(t("URL du serveur invalide."))
            return
        }
        let client = LiteLLMClient(baseURL: url, apiKey: proxy.masterKey())
        do {
            let reply = try await client.testChatCompletion(model: exposedModel)
            testState = .ok(reply)
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }

    private func copyConfig() {
        _ = ShareConfig.copyToPasteboard(
            baseURL: proxy.baseURL?.absoluteString ?? "",
            apiKey: proxy.masterKey(),
            model: exposedModel
        )
        copied = true
    }

    /// Branche l'app elle-même sur le proxy local (URL + master key + modèle par défaut).
    private func applyToApp() {
        guard let url = proxy.baseURL else { return }
        settings.serverURL = url.absoluteString
        settings.apiKey = proxy.masterKey()
        settings.saveAPIKeyToKeychain()
        settings.defaultModel = exposedModel
        Task {
            let client = LiteLLMClient(baseURL: url, apiKey: proxy.masterKey())
            if let models = try? await client.listModels() {
                await MainActor.run {
                    settings.availableModels = models.map(\.id).sorted()
                }
            }
        }
    }

    private func previous() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    private func finish(openChat: Bool = false) {
        OnboardingState.complete()
        if openChat { onOpenChat?() }
        dismiss()
    }
}
