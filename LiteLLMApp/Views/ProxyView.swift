import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Fenêtre de gestion du proxy LiteLLM local : installation, démarrage/arrêt, configuration.
struct ProxyView: View {
    @EnvironmentObject private var proxy: ProxyManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showMasterKey = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusSection
                controlsSection
                modelsSection
                logsSection
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 600)
        .navigationTitle("Proxy LiteLLM local")
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
        case .notInstalled: return "Non installé"
        case .installing: return "Installation en cours…"
        case .installed: return "Installé (arrêté)"
        case .starting: return "Démarrage… (premier lancement : ~10–30 s)"
        case .running(let external): return external ? "En cours (démarré hors de l'app)" : "En cours d'exécution"
        case .stopping: return "Arrêt en cours…"
        case .failed(let message): return "Erreur : \(message)"
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
                Label("health OK", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if case .running = proxy.state {
                Button("Utiliser comme serveur") {
                    if let url = proxy.baseURL {
                        settings.serverURL = url.absoluteString
                    }
                }
                .help("Définir l'URL du serveur dans les réglages (\(proxy.baseURL?.absoluteString ?? ""))")
            }
            Button("Fermer") { dismiss() }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Contrôles

    private var controlsSection: some View {
        Form {
            Section("Proxy") {
                HStack {
                    if !proxy.isInstalled {
                        Button("Installer LiteLLM") { proxy.install() }
                            .disabled(proxy.isBusy)
                    }
                    if proxy.isInstalled, !proxy.isRunning, !proxy.canStop {
                        Button("Démarrer") { proxy.start() }
                            .disabled(proxy.isBusy)
                    }
                    if proxy.canStop {
                        Button("Arrêter", role: .destructive) { proxy.stop() }
                            .disabled(proxy.isStopping)
                    }
                    if proxy.isBusy { ProgressView().controlSize(.small) }
                    Spacer()
                }
                Stepper(value: Binding(
                    get: { proxy.settings.port },
                    set: { proxy.settings.port = $0; proxy.saveSettings() }
                ), in: 1024...65535) {
                    Text("Port : \(proxy.settings.port)")
                }
                .disabled(proxy.isRunning)
                TextField("Hôte", text: Binding(
                    get: { proxy.settings.host },
                    set: { proxy.settings.host = $0; proxy.saveSettings() }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(proxy.isRunning)
                if proxy.isRunning {
                    Text("Modifier le port ou l'hôte nécessite un redémarrage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Arrêter le proxy à la fermeture de l'app", isOn: Binding(
                    get: { proxy.settings.stopOnQuit },
                    set: { proxy.settings.stopOnQuit = $0; proxy.saveSettings() }
                ))
                Toggle("Démarrer automatiquement au lancement", isOn: Binding(
                    get: { proxy.settings.autoStart },
                    set: { proxy.settings.autoStart = $0; proxy.saveSettings() }
                ))
            }

            Section("Master key") {
                HStack {
                    if showMasterKey {
                        Text(proxy.masterKey())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("••••••••")
                    }
                    Button(showMasterKey ? "Masquer" : "Afficher") { showMasterKey.toggle() }
                    Button("Regénérer") {
                        let hex = String((0..<24).map { _ in "0123456789abcdef".randomElement()! })
                        try? KeychainService.save(account: KeychainService.masterKeyAccount, value: "sk-\(hex)")
                    }
                    .help("Nouvelle master key (stockée dans le trousseau). À synchroniser dans la clé API des réglages.")
                }
                Text("Stockée dans le trousseau macOS et écrite dans le config.yaml généré (fichier en 0600).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Modèles (config.yaml)

    private var modelsSection: some View {
        Form {
            Section {
                ForEach($proxy.settings.models) { $model in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Nom exposé (model_name)", text: $model.name)
                            TextField("Modèle LiteLLM (ex. openai/gpt-4o)", text: $model.providerModel)
                            Button(role: .destructive) {
                                proxy.settings.models.removeAll { $0.id == model.id }
                                proxy.saveSettings()
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        HStack {
                            SecureField("Clé API du fournisseur", text: $model.apiKey)
                            TextField("API base (optionnel)", text: $model.apiBase)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.id) { _, _ in proxy.saveSettings() }
                }
                .onChange(of: proxy.settings.models.count) { _, _ in proxy.saveSettings() }

                HStack {
                    Menu {
                        Button("OpenAI") { addModel(providerModel: "openai/", apiBase: "") }
                        Button("Anthropic") { addModel(providerModel: "anthropic/", apiBase: "") }
                        Button("Google Gemini") { addModel(providerModel: "gemini/", apiBase: "") }
                        Button("Mistral") { addModel(providerModel: "mistral/", apiBase: "") }
                        Button("Ollama (local)") { addModel(providerModel: "ollama/", apiBase: "http://127.0.0.1:11434") }
                        Button("Personnalisé") { addModel(providerModel: "", apiBase: "") }
                    } label: {
                        Label("Ajouter un modèle", systemImage: "plus.circle")
                    }
                    Spacer()
                    Button("Ouvrir le dossier Application Support") {
                        #if canImport(AppKit)
                        NSWorkspace.shared.open(ProxyPaths.appSupport())
                        #endif
                    }
                }
                Text("Les modèles sont écrits dans config.yaml au démarrage du proxy. Les changements de modèles/archive nécessitent un redémarrage du proxy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Modèles (config.yaml)")
            }
        }
        .formStyle(.grouped)
    }

    private func addModel(providerModel: String, apiBase: String) {
        proxy.settings.models.append(ProxyModel(providerModel: providerModel, apiBase: apiBase))
        proxy.saveSettings()
    }

    // MARK: - Journaux

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            logView(title: "Journal d'installation", text: proxy.installLog, visible: !proxy.installLog.isEmpty)
            logView(title: "Journal du proxy", text: proxy.proxyLog, visible: !proxy.proxyLog.isEmpty || proxy.isRunning)
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
