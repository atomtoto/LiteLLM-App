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
/// branchement automatique de l'app (et copie optionnelle pour d'autres outils).
struct OnboardingView: View {
    @EnvironmentObject private var proxy: ProxyManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    /// Appelé quand l'utilisateur choisit « Commencer à discuter ».
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
    private func tf(_ key: String, _ args: Any...) -> String { L10n.shared.t(key, arguments: args) }

    /// Nom du modèle exposé (celui qui sera testé et utilisé).
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
                .padding()
        }
        .frame(minWidth: 680, minHeight: 600)
        .animation(.default, value: step)
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(stepTitle)
                    .font(.title2.bold())
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count)) {
                    Text(tf("Étape %@ sur %@", step.rawValue + 1, Step.allCases.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 260)
            }
            Spacer()
            if step != .done {
                Button(t("Plus tard")) { finish() }
                    .help(t("Fermer l'assistant (vous pourrez le relancer depuis le menu IA)"))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var stepTitle: String {
        switch step {
        case .welcome: return t("Bienvenue dans LiteLLM-App")
        case .provider: return t("Choisissez votre fournisseur d'IA")
        case .credentials: return t("Indiquez votre clé API et le modèle à utiliser")
        case .setup: return t("Préparation du service IA")
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
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(t("Cette application peut :")).font(.headline)
            Label(t("Discuter avec l'IA directement dans cette app"), systemImage: "bubble.left.and.bubble.right")
            Label(t("Brancher vos outils existants sur n'importe quel fournisseur (OpenAI, Anthropic, Gemini, Mistral…) : le proxy convertit automatiquement les API."), systemImage: "arrow.triangle.2.circlepath")
                .fixedSize(horizontal: false, vertical: true)
            Text(t("Il vous faut simplement une clé API d'un fournisseur d'IA — ou Ollama, gratuit, qui fonctionne sur votre Mac sans clé. Comptez environ 5 minutes la première fois."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Picker(t("Langue"), selection: Binding(
                get: { L10n.shared.lang },
                set: { L10n.shared.lang = $0 }
            )) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .fixedSize()
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Vous avez déjà une clé ? Collez-la ici : le fournisseur est reconnu automatiquement."))
                        .font(.callout)
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
                    if !draft.apiKey.isEmpty, chosenPreset.id != ProviderPresets.custom.id {
                        Label(tf("Fournisseur reconnu : %@", t(chosenPreset.displayName)), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                }
                .padding(4)
            }
            Text(t("Sinon, cliquez sur le service dont vous avez (ou voulez créer) une clé API."))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 12)], spacing: 12) {
                ForEach(ProviderPresets.all) { p in
                    Button {
                        choose(p)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: p.systemImage)
                                .font(.title2)
                            Text(t(p.displayName))
                                .font(.headline)
                                .multilineTextAlignment(.center)
                            Text(t(p.tagline))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .padding(6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.bordered)
                    // « Personnalisé » est la valeur initiale : ne pas la montrer comme un choix.
                    .tint(chosenPreset.id == p.id && p.id != ProviderPresets.custom.id ? .accentColor : nil)
                }
            }
        }
    }

    private var credentialsStep: some View {
        ProviderFormView(model: $draft, initialPreset: chosenPreset)
            .frame(minHeight: 380)
    }

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("L'app installe et démarre un petit service local qui fait le lien avec votre fournisseur. Il ne faut rien faire : patientez simplement."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            checklistRow(t("Installer le service IA (une seule fois, quelques minutes)"),
                         done: proxy.isInstalled,
                         active: proxy.state == .installing)
            checklistRow(t("Démarrer le service IA"),
                         done: proxy.isRunning,
                         active: proxy.state == .starting || proxy.state == .stopping)

            if case .failed(let message) = proxy.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if proxy.isMissingPython {
                    Button(t("Installer les outils Apple")) { proxy.installCommandLineTools() }
                        .help(t("Ouvre l'installateur Apple. Quand il a terminé, cliquez sur « Réessayer »."))
                }
            }

            if !proxy.installLog.isEmpty || !proxy.proxyLog.isEmpty {
                DisclosureGroup(t("Détails techniques")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !proxy.installLog.isEmpty {
                            LogView(title: t("Journal d'installation"), text: proxy.installLog, height: 110)
                        }
                        if !proxy.proxyLog.isEmpty {
                            LogView(title: t("Journal du proxy"), text: proxy.proxyLog, height: 110)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .task {
            await runSetup()
        }
    }

    private func checklistRow(_ title: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if active {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
            .frame(width: 20)
            Text(title)
        }
        .font(.headline)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? t("Terminé") : active ? t("En cours") : t("En attente"))
    }

    private var testStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tf("Modèle testé : %@", exposedModel))
                .font(.headline)
            switch testState {
            case .idle, .testing:
                HStack { ProgressView().controlSize(.small); Text(t("Envoi d'un message de test à l'IA…")) }
            case .ok(let reply):
                Label(t("Le test a réussi : votre clé et votre modèle fonctionnent."), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text(tf("Réponse reçue : %@", reply))
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label(t("Le test a échoué"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(t("Revenez en arrière pour corriger la clé API ou le modèle, puis réessayez."))
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            if testState == .idle { await runTest() }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(t("C'est prêt !"), systemImage: "checkmark.seal.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)
            Text(tf("Fournisseur : %@ — Modèle : %@", t(chosenPreset.displayName), exposedModel))
            Text(t("L'app est configurée et le service IA démarrera automatiquement à chaque lancement. Vous pouvez ajouter d'autres fournisseurs plus tard via le bouton « Fournisseurs d'IA »."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox(t("Utiliser aussi l'IA dans d'autres outils (facultatif)")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("N'importe quel outil compatible OpenAI (curl, SDK Python, LangChain…) peut appeler cette URL avec cette clé : le proxy convertit automatiquement la requête dans le format de votre fournisseur."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = proxy.baseURL {
                        Text(tf("Base URL : %@", url.absoluteString + "/v1"))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button(t("Copier la configuration")) { copyConfig() }
                        if copied {
                            Label(t("Copié !"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
        .onAppear { applyToApp() }
    }

    // MARK: - Pied de page

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button(t("Précédent")) { previous() }
                    .disabled(setupBusy)
            }
            Spacer()
            switch step {
            case .welcome:
                Button(t("Commencer")) { step = .provider }
                    .keyboardShortcut(.defaultAction)
            case .provider:
                Button(t("Suivant")) { choose(chosenPreset) }
                    .keyboardShortcut(.defaultAction)
            case .credentials:
                if !isDraftValid {
                    Text(chosenPreset.requiresAPIKey ? t("Collez votre clé API pour continuer.") : t("Choisissez un modèle pour continuer."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button(t("Suivant")) {
                    commitDraft()
                    step = .setup
                }
                .disabled(!isDraftValid)
                .keyboardShortcut(.defaultAction)
            case .setup:
                if case .failed = proxy.state {
                    Button(t("Réessayer")) { Task { await runSetup() } }
                        .disabled(setupBusy)
                }
                Button(t("Suivant")) { step = .test }
                    .disabled(!proxy.isRunning || setupBusy)
                    .keyboardShortcut(.defaultAction)
            case .test:
                if case .failed = testState {
                    Button(t("Réessayer")) { Task { await runTest() } }
                    Button(t("Continuer quand même")) { step = .done }
                } else {
                    Button(t("Suivant")) { step = .done }
                        .disabled(testState == .testing || testState == .idle)
                        .keyboardShortcut(.defaultAction)
                }
            case .done:
                Button(t("Commencer à discuter")) { finish(openChat: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }

    // MARK: - Actions

    private var isDraftValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !draft.providerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (!chosenPreset.requiresAPIKey || !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func choose(_ p: ProviderPreset) {
        chosenPreset = p
        applyPresetToDraft(p)
        step = .credentials
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
        if draft.name.isEmpty || !p.knownModels.contains(where: { $0.id == draft.name }) {
            draft.name = modelID
        }
    }

    /// Ajoute le brouillon aux modèles du proxy, ou met à jour l'entrée existante
    /// (l'utilisateur a pu revenir en arrière pour corriger sa clé).
    private func commitDraft() {
        guard isDraftValid else { return }
        if let index = proxy.settings.models.firstIndex(where: { $0.id == draft.id }) {
            proxy.settings.models[index] = draft
        } else {
            proxy.settings.models.append(draft)
        }
        proxy.saveSettings()
        testState = .idle
    }

    /// Installe si besoin, puis démarre (ou redémarre pour appliquer le nouveau fournisseur).
    private func runSetup() async {
        guard !setupBusy else { return }
        setupBusy = true
        defer { setupBusy = false }
        if !proxy.isInstalled {
            _ = await proxy.installAndWait()
        }
        guard proxy.isInstalled else { return }
        if proxy.isRunning && proxy.needsRestart {
            await proxy.stopAndWait()
        }
        if !proxy.isRunning {
            _ = await proxy.startAndWait()
        }
        if proxy.isRunning, step == .setup {
            step = .test
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
            testState = .failed(FriendlyError.message(for: error))
        }
    }

    private func copyConfig() {
        ShareConfig.copyToPasteboard(
            baseURL: proxy.baseURL?.absoluteString ?? "",
            apiKey: proxy.masterKey(),
            model: exposedModel
        )
        copied = true
    }

    /// Branche l'app elle-même sur le proxy local et active le démarrage automatique.
    private func applyToApp() {
        guard let url = proxy.baseURL else { return }
        settings.connect(toProxyAt: url, masterKey: proxy.masterKey(), defaultModel: exposedModel)
        proxy.settings.autoStart = true
        proxy.saveSettings()
    }

    private func previous() {
        var target = Step(rawValue: step.rawValue - 1) ?? .welcome
        // Revenir sur l'étape d'installation relancerait tout : on saute au formulaire.
        if target == .setup || target == .test { target = .credentials }
        step = target
    }

    private func finish(openChat: Bool = false) {
        OnboardingState.complete()
        if openChat { onOpenChat?() }
        dismiss()
    }
}

/// Journal technique en lecture seule (police à chasse fixe, sélectionnable).
struct LogView: View {
    let title: String
    let text: String
    var height: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .defaultScrollAnchor(.bottom)
            .frame(height: height)
            .background(.background, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        }
    }
}
