import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Fenêtre de gestion du proxy LiteLLM local : installation, démarrage/arrêt,
/// fournisseurs connectés (cartes lisibles) et configuration à copier pour
/// brancher n'importe quel outil externe.
struct ProxyView: View {
    @EnvironmentObject private var proxy: ProxyManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showMasterKey = false
    @State private var showAddProvider = false
    @State private var newDraft = ProxyModel()
    @State private var shareModel = ""
    @State private var copied = false

    private var t: (String) -> String { L10n.shared.t }
    private func tf(_ key: String, _ args: CVarArg...) -> String { L10n.shared.t(key, args) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusSection
                if proxy.isRunning {
                    useElsewhereSection
                }
                providersSection
                controlsSection
                logsSection
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 600)
        .navigationTitle(t("Proxy LiteLLM local"))
        .sheet(isPresented: $showAddProvider) {
            VStack(spacing: 0) {
                ProviderFormView(model: $newDraft)
                    .padding()
                Divider()
                HStack {
                    Spacer()
                    Button(t("Annuler"), role: .cancel) { showAddProvider = false }
                    Button(t("Ajouter un fournisseur")) {
                        proxy.settings.models.append(newDraft)
                        proxy.saveSettings()
                        showAddProvider = false
                        newDraft = ProxyModel()
                    }
                    .disabled(newDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || newDraft.providerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return)
                }
                .padding()
            }
            .frame(minWidth: 560, minHeight: 480)
        }
        .onAppear {
            if shareModel.isEmpty {
                shareModel = validModels.first?.name ?? ""
            }
        }
        .onChange(of: proxy.settings.models.count) { _, _ in
            if shareModel.isEmpty || !validModels.contains(where: { $0.name == shareModel }) {
                shareModel = validModels.first?.name ?? ""
            }
        }
    }

    private var validModels: [ProxyModel] {
        proxy.settings.models.filter { !$0.name.isEmpty && !$0.providerModel.isEmpty }
    }

    // MARK: - État

    private var stateColor: Color {
        switch proxy.state {
        case .running: return .green
        case .starting, .installing, .stopping: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }

    private var stateLabel: String {
        switch proxy.state {
        case .notInstalled: return t("Non installé")
        case .installing: return t("Installation en cours…")
        case .installed: return t("Installé (arrêté)")
        case .starting: return t("Démarrage… (premier lancement : ~10–30 s)")
        case .running(let external): return external ? t("En cours (démarré hors de l'app)") : t("En cours d'exécution")
        case .stopping: return t("Arrêt en cours…")
        case .failed(let message): return tf("Erreur : %@", message)
        }
    }

    private var statusSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .foregroundStyle(stateColor)
            Text(stateLabel)
                .font(.headline)
            Spacer()
            if proxy.isHealthy {
                Label(t("health OK"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if case .running = proxy.state, let url = proxy.baseURL {
                Button(t("Utiliser comme serveur")) {
                    settings.serverURL = url.absoluteString
                }
                .help(tf("Définir l'URL du serveur dans les réglages (%@)", url.absoluteString))
            }
            Button(t("Fermer")) { dismiss() }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Utiliser ce proxy ailleurs

    private var useElsewhereSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Utiliser ce proxy ailleurs")).font(.headline)
            Text(t("N'importe quel outil compatible OpenAI (curl, SDK Python, LangChain…) peut appeler cette URL avec cette clé : le proxy convertit automatiquement la requête dans le format de votre fournisseur."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: Alignment(horizontal: .leading, vertical: .center)) {
                GridRow {
                    Text(t("Base URL")).foregroundStyle(.secondary)
                    Text((proxy.baseURL?.absoluteString ?? "") + "/v1")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        ShareConfig.copyValue((proxy.baseURL?.absoluteString ?? "") + "/v1")
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain)
                    .help(t("Copier"))
                }
                GridRow {
                    Text(t("Clé API (master key)")).foregroundStyle(.secondary)
                    Group {
                        if showMasterKey {
                            Text(proxy.masterKey())
                        } else {
                            Text("••••••••••••")
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    HStack(spacing: 4) {
                        Button { showMasterKey.toggle() } label: {
                            Image(systemName: showMasterKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        Button {
                            ShareConfig.copyValue(proxy.masterKey())
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain)
                        .help(t("Copier"))
                    }
                }
                if !validModels.isEmpty {
                    GridRow {
                        Text(t("Modèle")).foregroundStyle(.secondary)
                        Picker(t("Modèle"), selection: $shareModel) {
                            ForEach(validModels) { m in
                                Text(m.name).tag(m.name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 320)
                        Button {
                            ShareConfig.copyValue(shareModel)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain)
                        .help(t("Copier"))
                    }
                }
            }

            HStack {
                Button(t("Copier la configuration complète")) {
                    _ = ShareConfig.copyToPasteboard(
                        baseURL: proxy.baseURL?.absoluteString ?? "",
                        apiKey: proxy.masterKey(),
                        model: shareModel
                    )
                    copied = true
                }
                if copied {
                    Label(t("Copié !"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Spacer()
                Button(t("Utiliser comme serveur")) {
                    if let url = proxy.baseURL {
                        settings.serverURL = url.absoluteString
                        settings.apiKey = proxy.masterKey()
                        settings.saveAPIKeyToKeychain()
                        if !shareModel.isEmpty { settings.defaultModel = shareModel }
                    }
                }
                .help(tf("Définir l'URL du serveur dans les réglages (%@)", proxy.baseURL?.absoluteString ?? ""))
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Fournisseurs

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Fournisseurs connectés")).font(.headline)
            if proxy.settings.models.isEmpty {
                Text(t("Aucun fournisseur pour l'instant — ajoutez votre clé API pour commencer."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach($proxy.settings.models) { $model in
                ProviderCardView(model: $model)
            }
            Button {
                newDraft = ProxyModel()
                showAddProvider = true
            } label: {
                Label(t("Ajouter un fournisseur"), systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Contrôles

    private var controlsSection: some View {
        Form {
            Section(t("Proxy")) {
                HStack {
                    if !proxy.isInstalled {
                        Button(t("Installer LiteLLM")) { proxy.install() }
                            .disabled(proxy.isBusy)
                    }
                    if proxy.isInstalled, !proxy.isRunning, !proxy.canStop {
                        Button(t("Démarrer")) { proxy.start() }
                            .disabled(proxy.isBusy)
                    }
                    if proxy.canStop {
                        Button(t("Arrêter"), role: .destructive) { proxy.stop() }
                            .disabled(proxy.isStopping)
                    }
                    if proxy.isBusy { ProgressView().controlSize(.small) }
                    Spacer()
                }
                Stepper(value: Binding(
                    get: { proxy.settings.port },
                    set: { proxy.settings.port = $0; proxy.saveSettings() }
                ), in: 1024...65535) {
                    Text(tf("Port : %@", proxy.settings.port))
                }
                .disabled(proxy.isRunning)
                TextField(t("Hôte"), text: Binding(
                    get: { proxy.settings.host },
                    set: { proxy.settings.host = $0; proxy.saveSettings() }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(proxy.isRunning)
                if proxy.isRunning {
                    Text(t("Modifier le port ou l'hôte nécessite un redémarrage."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(t("Arrêter le proxy à la fermeture de l'app"), isOn: Binding(
                    get: { proxy.settings.stopOnQuit },
                    set: { proxy.settings.stopOnQuit = $0; proxy.saveSettings() }
                ))
                Toggle(t("Démarrer automatiquement au lancement"), isOn: Binding(
                    get: { proxy.settings.autoStart },
                    set: { proxy.settings.autoStart = $0; proxy.saveSettings() }
                ))
            }

            Section(t("Master key")) {
                HStack {
                    if showMasterKey {
                        Text(proxy.masterKey())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("••••••••")
                    }
                    Button(showMasterKey ? t("Masquer") : t("Afficher")) { showMasterKey.toggle() }
                    Button(t("Regénérer")) {
                        let hex = String((0..<24).map { _ in "0123456789abcdef".randomElement()! })
                        try? KeychainService.save(account: KeychainService.masterKeyAccount, value: "sk-\(hex)")
                    }
                    .help(t("Nouvelle master key (stockée dans le trousseau). À synchroniser dans la clé API des réglages."))
                }
                Text(t("Stockée dans le trousseau macOS et écrite dans le config.yaml généré (fichier en 0600)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup(t("Avancé")) {
                ForEach($proxy.settings.models) { $model in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField(t("Nom exposé (model_name)"), text: $model.name)
                            TextField(t("Modèle LiteLLM (ex. openai/gpt-4o)"), text: $model.providerModel)
                        }
                        HStack {
                            SecureField(t("Clé API du fournisseur"), text: $model.apiKey)
                            TextField(t("API base (optionnel)"), text: $model.apiBase)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.name) { _, _ in proxy.saveSettings() }
                    .onChange(of: model.providerModel) { _, _ in proxy.saveSettings() }
                    .onChange(of: model.apiKey) { _, _ in proxy.saveSettings() }
                    .onChange(of: model.apiBase) { _, _ in proxy.saveSettings() }
                }
                Text(t("Les modèles sont écrits dans config.yaml au démarrage du proxy. Les changements de modèles/archive nécessitent un redémarrage du proxy."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(t("Ouvrir le dossier Application Support")) {
                    #if canImport(AppKit)
                    NSWorkspace.shared.open(ProxyPaths.appSupport())
                    #endif
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Journaux

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            logView(title: t("Journal d'installation"), text: proxy.installLog, visible: !proxy.installLog.isEmpty)
            logView(title: t("Journal du proxy"), text: proxy.proxyLog, visible: !proxy.proxyLog.isEmpty || proxy.isRunning)
        }
    }

    private func logView(title: String, text: String, visible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if visible {
                TextEditor(text: .constant(text))
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 160)
                    .scrollDisabled(false)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            }
        }
    }
}
