import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Fenêtre « Fournisseurs d'IA » : état du service local (proxy LiteLLM), fournisseurs
/// connectés, configuration à copier pour d'autres outils, et réglages avancés.
struct ProxyView: View {
    @EnvironmentObject private var proxy: ProxyManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showMasterKey = false
    @State private var showAddProvider = false
    @State private var newDraft = ProxyModel()
    @State private var shareModel = ""
    @State private var copied = false
    @State private var confirmRegenerate = false

    private var t: (String) -> String { L10n.shared.t }
    private func tf(_ key: String, _ args: Any...) -> String { L10n.shared.t(key, arguments: args) }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                providersSection
                if proxy.isRunning {
                    useElsewhereSection
                }
                optionsSection
                advancedSection
            }
            .formStyle(.grouped)
            .navigationTitle(t("Fournisseurs d'IA"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Terminé")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 680)
        .sheet(isPresented: $showAddProvider) {
            addProviderSheet
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
        case .installed: return t("Arrêté")
        case .starting: return t("Démarrage… (premier lancement : ~10–30 s)")
        case .running(let external): return external ? t("En cours (démarré hors de l'app)") : t("En cours d'exécution")
        case .stopping: return t("Arrêt en cours…")
        case .failed: return t("Problème")
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent {
                HStack {
                    if proxy.isBusy {
                        ProgressView().controlSize(.small)
                    }
                    mainControl
                }
            } label: {
                Label {
                    Text(stateLabel)
                } icon: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(stateColor)
                        .imageScale(.small)
                }
                .font(.headline)
            }

            if case .failed(let message) = proxy.state {
                Text(message)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if proxy.isMissingPython {
                    Button(t("Installer les outils Apple")) { proxy.installCommandLineTools() }
                }
            }

            if proxy.needsRestart {
                LabeledContent {
                    Button(t("Redémarrer maintenant")) { proxy.restart() }
                        .buttonStyle(.borderedProminent)
                } label: {
                    Label(t("Redémarrez le service pour appliquer vos modifications."), systemImage: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if proxy.isRunning, !settings.isConnected(to: proxy.baseURL), let url = proxy.baseURL {
                LabeledContent {
                    Button(t("Connecter l'app")) {
                        settings.connect(toProxyAt: url, masterKey: proxy.masterKey(),
                                         defaultModel: settings.defaultModel.isEmpty ? shareModel : nil)
                    }
                } label: {
                    Text(t("Le chat de l'app utilise un autre serveur."))
                    Text(t("Branchez le chat sur ce service pour discuter avec vos fournisseurs."))
                }
            }
        } header: {
            Text(t("Service IA local"))
        } footer: {
            Text(t("Un petit service (LiteLLM) tourne sur votre Mac et relaie vos messages vers le fournisseur choisi. Vos clés restent sur votre Mac."))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mainControl: some View {
        if !proxy.isInstalled {
            Button(t("Installer")) { proxy.install() }
                .buttonStyle(.borderedProminent)
                .disabled(proxy.isBusy)
        } else if proxy.canStop {
            Button(t("Arrêter")) { proxy.stop() }
                .disabled(proxy.isStopping)
        } else if !proxy.isRunning {
            Button(t("Démarrer")) { proxy.start() }
                .buttonStyle(.borderedProminent)
                .disabled(proxy.isBusy)
        }
    }

    // MARK: - Fournisseurs

    private var providersSection: some View {
        Section {
            if proxy.settings.models.isEmpty {
                Text(t("Aucun fournisseur pour l'instant — ajoutez votre clé API pour commencer."))
                    .foregroundStyle(.secondary)
            }
            ForEach($proxy.settings.models) { $model in
                ProviderCardView(model: $model)
            }
            Button {
                newDraft = ProxyModel()
                showAddProvider = true
            } label: {
                Label(t("Ajouter un fournisseur"), systemImage: "plus")
            }
        } header: {
            Text(t("Fournisseurs connectés"))
        }
    }

    private var addProviderSheet: some View {
        NavigationStack {
            ProviderFormView(model: $newDraft)
                .navigationTitle(t("Ajouter un fournisseur"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("Annuler")) { showAddProvider = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(t("Ajouter")) {
                            proxy.settings.models.append(newDraft)
                            proxy.saveSettings()
                            showAddProvider = false
                            newDraft = ProxyModel()
                            // Applique tout de suite le nouveau fournisseur.
                            if proxy.isRunning { proxy.restart() }
                        }
                        .disabled(newDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || newDraft.providerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - Utiliser ce proxy ailleurs

    private var useElsewhereSection: some View {
        Section {
            DisclosureGroup(t("Utiliser ce proxy ailleurs")) {
                Text(t("N'importe quel outil compatible OpenAI (curl, SDK Python, LangChain…) peut appeler cette URL avec cette clé : le proxy convertit automatiquement la requête dans le format de votre fournisseur."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                copyRow(t("Base URL"), value: (proxy.baseURL?.absoluteString ?? "") + "/v1")
                LabeledContent(t("Clé API (master key)")) {
                    HStack {
                        Text(showMasterKey ? proxy.masterKey() : "••••••••••••")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            showMasterKey.toggle()
                        } label: {
                            Label(showMasterKey ? t("Masquer") : t("Afficher"),
                                  systemImage: showMasterKey ? "eye.slash" : "eye")
                        }
                        copyButton(proxy.masterKey())
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
                if !validModels.isEmpty {
                    Picker(t("Modèle"), selection: $shareModel) {
                        ForEach(validModels) { m in
                            Text(m.name).tag(m.name)
                        }
                    }
                }
                HStack {
                    Button(t("Copier la configuration complète")) {
                        ShareConfig.copyToPasteboard(
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
                }
            }
        }
    }

    private func copyRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            HStack {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                copyButton(value)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
        }
    }

    private func copyButton(_ value: String) -> some View {
        Button {
            ShareConfig.copyValue(value)
        } label: {
            Label(t("Copier"), systemImage: "doc.on.doc")
        }
        .help(t("Copier"))
    }

    // MARK: - Options

    private var optionsSection: some View {
        Section(t("Options")) {
            Toggle(t("Démarrer automatiquement au lancement"), isOn: Binding(
                get: { proxy.settings.autoStart },
                set: { proxy.settings.autoStart = $0; proxy.saveSettings() }
            ))
            Toggle(t("Arrêter le proxy à la fermeture de l'app"), isOn: Binding(
                get: { proxy.settings.stopOnQuit },
                set: { proxy.settings.stopOnQuit = $0; proxy.saveSettings() }
            ))
        }
    }

    // MARK: - Avancé

    private var advancedSection: some View {
        Section {
            DisclosureGroup(t("Avancé")) {
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
                .disabled(proxy.isRunning)
                if proxy.isRunning {
                    Text(t("Modifier le port ou l'hôte nécessite un redémarrage."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent(t("Master key")) {
                    HStack {
                        Text(showMasterKey ? proxy.masterKey() : "••••••••")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Button(showMasterKey ? t("Masquer") : t("Afficher")) { showMasterKey.toggle() }
                        Button(t("Regénérer…")) { confirmRegenerate = true }
                    }
                }
                Text(t("Stockée dans le trousseau macOS et écrite dans le config.yaml généré (fichier en 0600)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                    .onChange(of: model) { _, _ in proxy.saveSettings() }
                }

                Button(t("Ouvrir le dossier Application Support")) {
                    #if canImport(AppKit)
                    NSWorkspace.shared.open(ProxyPaths.appSupport())
                    #endif
                }

                if !proxy.installLog.isEmpty {
                    LogView(title: t("Journal d'installation"), text: proxy.installLog)
                }
                if !proxy.proxyLog.isEmpty {
                    LogView(title: t("Journal du proxy"), text: proxy.proxyLog)
                }
            }
        }
        .confirmationDialog(t("Regénérer la master key ?"), isPresented: $confirmRegenerate) {
            Button(t("Regénérer"), role: .destructive) { regenerateMasterKey() }
        } message: {
            Text(t("Les outils externes utilisant l'ancienne clé devront être mis à jour. Le service redémarrera et l'app sera mise à jour automatiquement."))
        }
    }

    private func regenerateMasterKey() {
        let wasConnected = settings.isConnected(to: proxy.baseURL)
        let key = proxy.regenerateMasterKey()
        if wasConnected {
            settings.apiKey = key
            settings.saveAPIKeyToKeychain()
        }
    }
}
